package com.manisa.manisa_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import android.util.Log
import chip.devicecontroller.AttestationTrustStoreDelegate
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ClusterIDMapping.OnOff
import chip.devicecontroller.CommissionParameters
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.DeviceAttestation
import chip.devicecontroller.GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback
import chip.devicecontroller.InvokeCallback
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.UnpairDeviceCallback
import chip.devicecontroller.ReportCallback
import chip.devicecontroller.ResubscriptionAttemptCallback
import chip.devicecontroller.SubscriptionEstablishedCallback
import chip.devicecontroller.model.ChipAttributePath
import chip.devicecontroller.model.ChipPathId
import chip.devicecontroller.model.ChipEventPath
import chip.devicecontroller.model.InvokeElement
import chip.devicecontroller.model.NodeState
import chip.platform.AndroidBleManager
import chip.platform.AndroidChipPlatform
import chip.platform.AndroidNfcCommissioningManager
import chip.platform.ChipMdnsCallbackImpl
import chip.platform.DiagnosticDataProviderImpl
import chip.platform.NsdManagerServiceBrowser
import chip.platform.NsdManagerServiceResolver
import chip.platform.PreferencesConfigurationManager
import chip.platform.PreferencesKeyValueStoreManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Arrays
import matter.onboardingpayload.OnboardingPayloadParser
import matter.tlv.AnonymousTag
import matter.tlv.TlvReader
import matter.tlv.TlvWriter

/**
 * M1 Android Matter bridge.
 *
 * Commissioning deliberately follows the BLE rendezvous path used by the official Matter
 * CHIPTool: QR parse -> BLE scan by discriminator -> GATT -> pairDeviceThroughBLE -> Wi-Fi.
 * This is the same transport path already proven on the Manisa test hardware.
 */
class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        // One controller per Android process, including Activity recreation.
        private var sharedPlatform: AndroidChipPlatform? = null
        private var sharedController: ChipDeviceController? = null
        private val pendingRemovals = mutableSetOf<Long>()
        private const val TAG = "ManisaMatter"
        private const val METHODS = "com.manisa/matter/methods"
        private const val EVENTS = "com.manisa/matter/events"
        private const val VENDOR_ID = 0xFFF4
        private const val STATUS_OK = 0L
        private const val PERMISSION_REQUEST_MATTER = 9101
        private const val DEVICE_ATTESTATION_TIMEOUT = 600
    }

    private data class CommissionRequest(
        val setupPayload: String,
        val ssid: String,
        val password: String,
        val result: MethodChannel.Result,
    )

    private lateinit var platform: AndroidChipPlatform
    private lateinit var controller: ChipDeviceController
    private var initializationError: Throwable? = null
    private var bleCommissioner: ManisaBleCommissioner? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingCommission: MethodChannel.Result? = null
    private var pendingCommissionNodeId: Long = 0
    private var pendingPermissionCommission: CommissionRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(this)
        try {
            Log.i(TAG, "Initializing Matter runtime")
            initializeMatter()
            Log.i(TAG, "Matter runtime ready")
        } catch (error: Exception) {
            initializationError = error
            Log.e(TAG, "Matter initialization failed", error)
        } catch (error: LinkageError) {
            initializationError = error
            Log.e(TAG, "Matter native library loading failed", error)
        }
    }

    private fun initializeMatter() {
        ChipDeviceController.loadJni()
        platform = sharedPlatform ?: AndroidChipPlatform(
            AndroidBleManager(applicationContext),
            AndroidNfcCommissioningManager(),
            PreferencesKeyValueStoreManager(applicationContext),
            PreferencesConfigurationManager(applicationContext),
            NsdManagerServiceResolver(
                applicationContext,
                NsdManagerServiceResolver.NsdManagerResolverAvailState(),
            ),
            NsdManagerServiceBrowser(applicationContext),
            ChipMdnsCallbackImpl(),
            DiagnosticDataProviderImpl(applicationContext),
        ).also { sharedPlatform = it }
        controller = sharedController ?: ChipDeviceController(
            ControllerParams.newBuilder()
                .setControllerVendorId(VENDOR_ID)
                .setEnableServerInteractions(true)
                .build(),
        ).also { sharedController = it }
        controller.setAttestationTrustStoreDelegate(ManisaTestAttestationTrustStore())

        // M1 validation devices use development credentials. Match CHIPTool's behavior and
        // explicitly continue after the attestation callback. Production will replace this with
        // strict PAA/DCL verification before release.
        controller.setDeviceAttestationDelegate(DEVICE_ATTESTATION_TIMEOUT) {
            devicePtr,
            _,
            errorCode ->
            Log.i(TAG, "Device attestation completed errorCode=$errorCode")
            runOnUiThread {
                controller.continueCommissioning(devicePtr, true)
            }
        }
        controller.setCompletionListener(commissioningListener)
        controller.startDnssd()
        Log.i(TAG, "Matter operational discovery ready; controllerNodeId=${controller.controllerNodeId}")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        initializationError?.let { error ->
            result.error(
                "matter_initialization_failed",
                "Matter could not start: ${error.javaClass.simpleName}: ${error.message}",
                null,
            )
            return
        }
        try {
            when (call.method) {
                "isSupported" -> result.success(true)
                "commissionWifi" -> commissionWifi(call, result)
                "discoverOnOffEndpoints" -> withNodeId(call, result) { nodeId ->
                    discoverOnOffEndpoints(nodeId, result, subscribe = true)
                }
                "readOnOff" -> withNodeAndEndpoint(call, result) { nodeId, endpoint ->
                    readOnOff(nodeId, endpoint, result)
                }
                "setOnOff" -> withNodeAndEndpoint(call, result) { nodeId, endpoint ->
                    val value = call.argument<Boolean>("value")
                        ?: return@withNodeAndEndpoint result.error(
                            "invalid_args",
                            "value is required",
                            null,
                        )
                    invokeOnOff(
                        nodeId,
                        endpoint,
                        if (value) OnOff.Command.On else OnOff.Command.Off,
                        result,
                    )
                }
                "toggleOnOff" -> withNodeAndEndpoint(call, result) { nodeId, endpoint ->
                    invokeOnOff(nodeId, endpoint, OnOff.Command.Toggle, result)
                }
                "removeDevice" -> withNodeId(call, result) { nodeId ->
                    removeDevice(nodeId, result)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            Log.e(TAG, "Matter method ${call.method} failed", error)
            result.error("matter_exception", error.message, null)
        }
    }

    private fun commissionWifi(call: MethodCall, result: MethodChannel.Result) {
        Log.i(TAG, "commissionWifi request received")
        if (pendingCommission != null || pendingPermissionCommission != null) {
            result.error(
                "commissioning_busy",
                "Another Matter device is already being commissioned",
                null,
            )
            return
        }

        val setupPayload = call.argument<String>("setupPayload")?.trim().orEmpty()
        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        val password = call.argument<String>("password").orEmpty()
        if (!setupPayload.startsWith("MT:", ignoreCase = true) || ssid.isEmpty()) {
            result.error(
                "invalid_args",
                "Valid Matter setup payload and Wi-Fi SSID are required",
                null,
            )
            return
        }

        val request = CommissionRequest(setupPayload, ssid, password, result)
        val missingPermissions = requiredMatterPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missingPermissions.isNotEmpty()) {
            pendingPermissionCommission = request
            requestPermissions(missingPermissions.toTypedArray(), PERMISSION_REQUEST_MATTER)
            return
        }
        startCommissionWifi(request)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_MATTER) return

        val pending = pendingPermissionCommission ?: return
        pendingPermissionCommission = null
        val granted = grantResults.isNotEmpty() && grantResults.all {
            it == PackageManager.PERMISSION_GRANTED
        }
        if (!granted) {
            pending.result.error(
                "matter_permission_denied",
                "Bluetooth permission is required to add a Matter device",
                null,
            )
            return
        }
        startCommissionWifi(pending)
    }

    private fun requiredMatterPermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun startCommissionWifi(request: CommissionRequest) {
        val payload = try {
            OnboardingPayloadParser().parseQrCode(request.setupPayload.uppercase())
        } catch (error: Throwable) {
            request.result.error(
                "invalid_matter_qr",
                "Matter QR payload could not be parsed",
                error.message,
            )
            return
        }

        val nodeId = nextNodeId()
        val network = NetworkCredentials.forWiFi(
            NetworkCredentials.WiFiCredentials(request.ssid, request.password),
        )
        val params = CommissionParameters.Builder()
            .setCsrNonce(null)
            .setNetworkCredentials(network)
            .setICDRegistrationInfo(null)
            .build()

        pendingCommission = request.result
        pendingCommissionNodeId = nodeId
        controller.setCompletionListener(commissioningListener)

        val discriminator = payload.getLongDiscriminatorValue()
        val isShortDiscriminator = payload.hasShortDiscriminator
        val setupPinCode = payload.setupPinCode

        Log.i(
            TAG,
            "Starting CHIPTool-compatible BLE commissioning nodeId=$nodeId " +
                "discriminator=$discriminator short=$isShortDiscriminator",
        )

        bleCommissioner?.cancel()
        bleCommissioner = ManisaBleCommissioner(this, platform).also { commissioner ->
            commissioner.start(
                discriminator = discriminator,
                isShortDiscriminator = isShortDiscriminator,
                connected = { gatt, connectionId ->
                    try {
                        Log.i(TAG, "BLE rendezvous ready connectionId=$connectionId")
                        controller.pairDeviceThroughBLE(
                            gatt,
                            connectionId,
                            nodeId,
                            setupPinCode,
                            params,
                        )
                    } catch (error: Throwable) {
                        failPendingCommission(
                            "matter_ble_pairing_failed",
                            error.message ?: "Unable to start Matter BLE pairing",
                            null,
                        )
                    }
                },
                failed = { message ->
                    failPendingCommission("matter_ble_failed", message, null)
                },
            )
        }
    }

    private val commissioningListener = object : GenericChipDeviceListener() {
        override fun onPairingComplete(code: Long) {
            Log.i(TAG, "Matter pairing complete errorCode=$code")
            if (code != STATUS_OK && pendingCommission != null) {
                failPendingCommission(
                    "pairing_failed",
                    "Matter pairing failed (error $code)",
                    code,
                )
            }
        }

        override fun onCommissioningStatusUpdate(nodeId: Long, stage: String, errorCode: Long) {
            Log.i(
                TAG,
                "Commissioning status nodeId=$nodeId stage=$stage errorCode=$errorCode",
            )
        }

        override fun onCommissioningStageStart(nodeId: Long, stage: String) {
            Log.i(TAG, "Commissioning stage started nodeId=$nodeId stage=$stage")
        }

        override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
            Log.i(TAG, "Matter commissioning complete nodeId=$nodeId errorCode=$errorCode")
            val pending = pendingCommission ?: return
            if (nodeId != pendingCommissionNodeId) return

            if (errorCode != STATUS_OK) {
                failPendingCommission(
                    "commissioning_failed",
                    "Matter commissioning failed (error $errorCode)",
                    errorCode,
                )
                return
            }

            discoverOnOffEndpoints(
                nodeId,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val endpoints = result as? List<*> ?: emptyList<Any>()
                        pendingCommission = null
                        pendingCommissionNodeId = 0
                        bleCommissioner = null
                        pending.success(
                            mapOf(
                                "nodeId" to nodeId,
                                "onOffEndpoints" to endpoints,
                            ),
                        )
                    }

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        pendingCommission = null
                        pendingCommissionNodeId = 0
                        bleCommissioner = null
                        pending.error(errorCode, errorMessage, errorDetails)
                    }

                    override fun notImplemented() {
                        pendingCommission = null
                        pendingCommissionNodeId = 0
                        bleCommissioner = null
                        pending.notImplemented()
                    }
                },
                subscribe = true,
            )
        }

        override fun onError(error: Throwable?) {
            Log.e(TAG, "Matter commissioning listener error", error)
            if (pendingCommission != null) {
                failPendingCommission(
                    "commissioning_error",
                    error?.message ?: "Matter commissioning error",
                    null,
                )
            }
        }
    }

    private fun failPendingCommission(code: String, message: String, details: Any?) {
        val pending = pendingCommission ?: return
        pendingCommission = null
        pendingCommissionNodeId = 0
        bleCommissioner?.cancel()
        bleCommissioner = null
        runOnUiThread {
            pending.error(code, message, details)
        }
    }

    private fun removeDevice(nodeId: Long, result: MethodChannel.Result) {
        if (!pendingRemovals.add(nodeId)) {
            result.error("removal_busy", "Device removal is already in progress", nodeId)
            return
        }
        Log.i(TAG, "Requesting removal of current fabric from nodeId=$nodeId")
        try {
            controller.unpairDeviceCallback(nodeId, object : UnpairDeviceCallback {
                override fun onSuccess(remoteDeviceId: Long) {
                    runOnUiThread {
                        pendingRemovals.remove(nodeId)
                        Log.i(TAG, "Device confirmed fabric removal nodeId=$remoteDeviceId")
                        result.success(null)
                    }
                }

                override fun onError(status: Int, remoteDeviceId: Long) {
                    runOnUiThread {
                        pendingRemovals.remove(nodeId)
                        Log.e(TAG, "Fabric removal failed nodeId=$remoteDeviceId status=$status")
                        result.error("matter_remove_failed", "Device did not confirm removal (error $status)", remoteDeviceId)
                    }
                }
            })
        } catch (error: Exception) {
            pendingRemovals.remove(nodeId)
            throw error
        }
    }

    private fun discoverOnOffEndpoints(
        nodeId: Long,
        result: MethodChannel.Result,
        subscribe: Boolean,
    ) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            controller.readPath(
                object : ReportCallback {
                    override fun onError(
                        attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?,
                        ex: Exception,
                    ) {
                        result.error("matter_read_failed", ex.message, null)
                    }

                    override fun onReport(nodeState: NodeState) {
                        val endpoints = nodeState.endpointStates
                            .filter { (_, endpointState) ->
                                endpointState.clusterStates.containsKey(OnOff.ID)
                            }
                            .keys
                            .map { it.toInt() }
                            .filter { it > 0 }
                            .sorted()
                        if (subscribe && endpoints.isNotEmpty()) {
                            subscribeOnOff(nodeId, devicePointer, endpoints)
                        }
                        result.success(endpoints)
                    }
                },
                devicePointer,
                // A null path list means no attributes, not a wildcard read.
                // Read OnOff on every endpoint to discover all switch channels.
                listOf(
                    ChipAttributePath.newInstance(
                        ChipPathId.forWildcard(),
                        ChipPathId.forId(OnOff.ID),
                        ChipPathId.forId(OnOff.Attribute.OnOff.id),
                    ),
                ),
                null,
                false,
                0,
            )
        }
    }

    private fun readOnOff(nodeId: Long, endpoint: Int, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            val path = ChipAttributePath.newInstance(
                endpoint,
                OnOff.ID,
                OnOff.Attribute.OnOff.id,
            )
            controller.readPath(
                object : ReportCallback {
                    override fun onError(
                        attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?,
                        ex: Exception,
                    ) {
                        result.error("matter_read_failed", ex.message, null)
                    }

                    override fun onReport(nodeState: NodeState) {
                        val tlv = nodeState
                            .getEndpointState(endpoint)
                            ?.getClusterState(OnOff.ID)
                            ?.getAttributeState(OnOff.Attribute.OnOff.id)
                            ?.tlv
                        if (tlv == null) {
                            result.error(
                                "missing_state",
                                "OnOff state was not returned",
                                null,
                            )
                            return
                        }
                        result.success(TlvReader(tlv).getBool(AnonymousTag))
                    }
                },
                devicePointer,
                listOf(path),
                null,
                false,
                0,
            )
        }
    }

    private fun invokeOnOff(
        nodeId: Long,
        endpoint: Int,
        command: OnOff.Command,
        result: MethodChannel.Result,
    ) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            val writer = TlvWriter()
            writer.startStructure(AnonymousTag)
            writer.endStructure()
            val invoke = InvokeElement.newInstance(
                endpoint,
                OnOff.ID,
                command.id,
                writer.getEncoded(),
                null,
            )
            controller.invoke(
                object : InvokeCallback {
                    override fun onError(ex: Exception?) {
                        result.error(
                            "matter_invoke_failed",
                            ex?.message ?: "Matter command failed",
                            null,
                        )
                    }

                    override fun onResponse(invokeElement: InvokeElement?, successCode: Long) {
                        if (successCode == STATUS_OK) {
                            result.success(null)
                        } else {
                            result.error(
                                "matter_invoke_failed",
                                "Matter command returned error",
                                successCode,
                            )
                        }
                    }
                },
                devicePointer,
                invoke,
                0,
                0,
            )
        }
    }

    private fun subscribeOnOff(nodeId: Long, devicePointer: Long, endpoints: List<Int>) {
        val paths = endpoints.map { endpoint ->
            ChipAttributePath.newInstance(
                endpoint,
                OnOff.ID,
                OnOff.Attribute.OnOff.id,
            )
        }
        controller.subscribeToPath(
            SubscriptionEstablishedCallback { subscriptionId ->
                Log.i(TAG, "OnOff subscription established: $subscriptionId")
            },
            ResubscriptionAttemptCallback { cause, delayMs ->
                Log.w(TAG, "Matter resubscribe cause=$cause delayMs=$delayMs")
            },
            object : ReportCallback {
                override fun onError(
                    attributePath: ChipAttributePath?,
                    eventPath: ChipEventPath?,
                    ex: Exception,
                ) {
                    Log.e(TAG, "OnOff subscription failed", ex)
                }

                override fun onReport(nodeState: NodeState) {
                    for (endpoint in endpoints) {
                        val tlv = nodeState
                            .getEndpointState(endpoint)
                            ?.getClusterState(OnOff.ID)
                            ?.getAttributeState(OnOff.Attribute.OnOff.id)
                            ?.tlv
                            ?: continue
                        val value = TlvReader(tlv).getBool(AnonymousTag)
                        runOnUiThread {
                            eventSink?.success(
                                mapOf(
                                    "nodeId" to nodeId,
                                    "endpoint" to endpoint,
                                    "value" to value,
                                ),
                            )
                        }
                    }
                }
            },
            devicePointer,
            paths,
            null,
            1,
            60,
            false,
            false,
            0,
        )
    }

    private fun withConnectedDevice(
        nodeId: Long,
        result: MethodChannel.Result,
        action: (Long) -> Unit,
    ) {
        controller.getConnectedDevicePointer(
            nodeId,
            object : GetConnectedDeviceCallback {
                override fun onDeviceConnected(devicePointer: Long) {
                    action(devicePointer)
                }

                override fun onConnectionFailure(nodeId: Long, error: Exception) {
                    result.error("matter_connection_failed", error.message, nodeId)
                }
            },
        )
    }

    private fun withNodeId(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (Long) -> Unit,
    ) {
        val nodeId = call.argument<Number>("nodeId")?.toLong()
        if (nodeId == null || nodeId <= 0) {
            result.error("invalid_args", "nodeId is required", null)
            return
        }
        action(nodeId)
    }

    private fun withNodeAndEndpoint(
        call: MethodCall,
        result: MethodChannel.Result,
        action: (Long, Int) -> Unit,
    ) {
        val nodeId = call.argument<Number>("nodeId")?.toLong()
        val endpoint = call.argument<Number>("endpoint")?.toInt()
        if (nodeId == null || nodeId <= 0 || endpoint == null || endpoint <= 0) {
            result.error("invalid_args", "nodeId and endpoint are required", null)
            return
        }
        action(nodeId, endpoint)
    }

    private fun nextNodeId(): Long {
        val preferences = getSharedPreferences("manisa_matter", Context.MODE_PRIVATE)
        val current = preferences.getLong("next_node_id", 1L).coerceAtLeast(1L)
        preferences.edit().putLong("next_node_id", current + 1L).apply()
        return current
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}

/** Test roots copied from the official CHIPTool v1.5.1.0 sample for M1 hardware validation. */
private class ManisaTestAttestationTrustStore : AttestationTrustStoreDelegate {
    private val paaCertificates = listOf(TEST_PAA_FFF1_CERT, TEST_PAA_NO_VID_CERT)

    override fun getProductAttestationAuthorityCert(skid: ByteArray): ByteArray? =
        paaCertificates
            .asSequence()
            .map { Base64.decode(it, Base64.DEFAULT) }
            .firstOrNull { certificate ->
                Arrays.equals(DeviceAttestation.extractSkidFromPaaCert(certificate), skid)
            }

    companion object {
        private const val TEST_PAA_FFF1_CERT =
            "MIIBvTCCAWSgAwIBAgIITqjoMYLUHBwwCgYIKoZIzj0EAwIwMDEYMBYGA1UEAwwP\n" +
                "TWF0dGVyIFRlc3QgUEFBMRQwEgYKKwYBBAGConwCAQwERkZGMTAgFw0yMTA2Mjgx\n" +
                "NDIzNDNaGA85OTk5MTIzMTIzNTk1OVowMDEYMBYGA1UEAwwPTWF0dGVyIFRlc3Qg\n" +
                "UEFBMRQwEgYKKwYBBAGConwCAQwERkZGMTBZMBMGByqGSM49AgEGCCqGSM49AwEH\n" +
                "A0IABLbLY3KIfyko9brIGqnZOuJDHK2p154kL2UXfvnO2TKijs0Duq9qj8oYShpQ\n" +
                "NUKWDUU/MD8fGUIddR6Pjxqam3WjZjBkMBIGA1UdEwEB/wQIMAYBAf8CAQEwDgYD\n" +
                "VR0PAQH/BAQDAgEGMB0GA1UdDgQWBBRq/SJ3H1Ef7L8WQZdnENzcMaFxfjAfBgNV\n" +
                "HSMEGDAWgBRq/SJ3H1Ef7L8WQZdnENzcMaFxfjAKBggqhkjOPQQDAgNHADBEAiBQ\n" +
                "qoAC9NkyqaAFOPZTaK0P/8jvu8m+t9pWmDXPmqdRDgIgI7rI/g8j51RFtlM5CBpH\n" +
                "mUkpxyqvChVI1A0DTVFLJd4="

        private const val TEST_PAA_NO_VID_CERT =
            "MIIBkTCCATegAwIBAgIHC4+6qN2G7jAKBggqhkjOPQQDAjAaMRgwFgYDVQQDDA9N\n" +
                "YXR0ZXIgVGVzdCBQQUEwIBcNMjEwNjI4MTQyMzQzWhgPOTk5OTEyMzEyMzU5NTla\n" +
                "MBoxGDAWBgNVBAMMD01hdHRlciBUZXN0IFBBQTBZMBMGByqGSM49AgEGCCqGSM49\n" +
                "AwEHA0IABBDvAqgah7aBIfuo0xl4+AejF+UKqKgoRGgokUuTPejt1KXDnJ/3Gkzj\n" +
                "ZH/X9iZTt9JJX8ukwPR/h2iAA54HIEqjZjBkMBIGA1UdEwEB/wQIMAYBAf8CAQEw\n" +
                "DgYDVR0PAQH/BAQDAgEGMB0GA1UdDgQWBBR4XOcFuGuPTm/Hk6pgy0PqaWiC1TAf\n" +
                "BgNVHSMEGDAWgBR4XOcFuGuPTm/Hk6pgy0PqaWiC1TAKBggqhkjOPQQDAgNIADBF\n" +
                "AiEAue/bPqBqUuwL8B5h2u0sLRVt22zwFBAdq3mPrAX6R+UCIGAGHT411g2dSw1E\n" +
                "ja12EvfoXFguP8MS3Bh5TdNzcV5d"
    }
}
