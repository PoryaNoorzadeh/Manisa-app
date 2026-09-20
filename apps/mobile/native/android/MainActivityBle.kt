package com.manisa.manisa_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import matter.tlv.ContextSpecificTag
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
        private const val LEVEL_EVENTS = "com.manisa/matter/level_events"
        private const val COLOR_EVENTS = "com.manisa/matter/color_events"
        private const val ELECTRICAL_EVENTS = "com.manisa/matter/electrical_events"
        private const val SENSOR_EVENTS = "com.manisa/matter/sensor_events"
        private val SENSOR_ATTRIBUTES = listOf(
            Triple(0x0402L, 0L, "temperature"),
            Triple(0x0405L, 0L, "humidity"),
            Triple(0x0406L, 0L, "occupancy"),
            Triple(0x0045L, 0L, "contactClosed"),
        )
        private const val COLOR_CLUSTER = 0x0300L
        // Attribute id -> wire name. Values >= 0x4000 plus x/y use uint16.
        private val COLOR_ATTRIBUTES = mapOf(
            0L to "hue", 1L to "saturation", 3L to "x", 4L to "y",
            8L to "mode", 0x4000L to "enhancedHue", 0x4001L to "enhancedMode",
            0x400AL to "capabilities",
        )
        private val ELECTRICAL_ATTRIBUTES = listOf(
            Triple(0x0090L, 4L, "voltageMillivolts"),
            Triple(0x0090L, 5L, "activeCurrentMilliamps"),
            Triple(0x0090L, 8L, "activePowerMilliwatts"),
            Triple(0x0091L, 1L, "cumulativeEnergyImportedMilliwattHours"),
        )
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
    private var levelEventSink: EventChannel.EventSink? = null
    private var colorEventSink: EventChannel.EventSink? = null
    private var electricalEventSink: EventChannel.EventSink? = null
    private var sensorEventSink: EventChannel.EventSink? = null
    private val sensorReadTokens = mutableMapOf<Long, Any>()
    private val sensorSubscriptionPaths = mutableMapOf<Long, List<Triple<Int, Long, Long>>>()
    private val sensorHandler = Handler(Looper.getMainLooper())
    private val subscriptionIds = mutableMapOf<Pair<Long, String>, Long>()
    private val subscriptionEpochs = mutableMapOf<Pair<Long, String>, Any>()
    private val colorCapabilities = mutableMapOf<Long, Map<Int, Int>>()
    private val colorLifetimes = mutableMapOf<Long, Any>()
    private val colorSubscriptionTokens = mutableMapOf<Long, Any>()
    private val colorSubscriptionPaths = mutableMapOf<Long, List<Pair<Int, Long>>>()
    private val electricalSubscriptionPaths =
        mutableMapOf<Long, List<Triple<Int, Long, Long>>>()
    private val levelSubscriptionEndpoints = mutableMapOf<Long, List<Int>>()
    private val onOffSubscriptionEndpoints = mutableMapOf<Long, List<Int>>()
    private var pendingCommission: MethodChannel.Result? = null
    private var pendingCommissionNodeId: Long = 0
    private var pendingPermissionCommission: CommissionRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COLOR_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    colorEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    colorEventSink = null
                }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LEVEL_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    levelEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    levelEventSink = null
                }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, ELECTRICAL_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    electricalEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    electricalEventSink = null
                }
            })
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SENSOR_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sensorEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    sensorEventSink = null
                }
            })
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
                "readDeviceTypes" -> withNodeId(call, result) { nodeId ->
                    readDeviceTypes(nodeId, result)
                }
                "readLevels" -> withNodeId(call, result) { nodeId ->
                    readLevels(nodeId, result)
                }
                "readColors" -> withNodeId(call, result) { nodeId ->
                    readColors(nodeId, result)
                }
                "setColor" -> withNodeAndEndpoint(call, result) { nodeId, endpoint ->
                    val mode = call.argument<String>("mode")
                    val first = call.argument<Number>("first")?.toInt()
                    val second = call.argument<Number>("second")?.toInt()
                    val maximum = if (mode == "hs") 254 else 65279
                    val capability = if (mode == "hs") 1 else 8
                    if ((mode != "hs" && mode != "xy") || first == null || second == null ||
                        first !in 0..maximum || second !in 0..maximum ||
                        (mode == "xy" && (second == 0 || first + second > 65536))) {
                        result.error("invalid_args", "Invalid color command", null)
                    } else if (((colorCapabilities[nodeId]?.get(endpoint) ?: 0) and capability) == 0) {
                        result.error("unsupported_color", "Read device color capabilities first", null)
                    } else {
                        invokeColor(nodeId, endpoint, mode, first, second, result)
                    }
                }
                "readSensorMeasurements" -> withNodeId(call, result) { nodeId ->
                    readSensorMeasurements(nodeId, result)
                }
                "readElectricalMeasurements" -> withNodeId(call, result) { nodeId ->
                    readElectricalMeasurements(nodeId, result)
                }
                "setLevel" -> withNodeAndEndpoint(call, result) { nodeId, endpoint ->
                    val level = call.argument<Number>("level")?.toInt()
                    if (level == null || level !in 1..254) {
                        result.error("invalid_args", "level must be between 1 and 254", null)
                    } else {
                        invokeLevel(nodeId, endpoint, level, result)
                    }
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
                        // Pairing succeeded. Optional OnOff discovery must not lose
                        // a sensor-only node that has already joined this fabric.
                        Log.w(TAG, "Post-commission OnOff discovery unavailable: $errorCode")
                        success(emptyList<Any>())
                    }

                    override fun notImplemented() {
                        success(emptyList<Any>())
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
                        levelSubscriptionEndpoints.remove(nodeId)
                        onOffSubscriptionEndpoints.remove(nodeId)
                        subscriptionEpochs.keys.filter { it.first == nodeId }.toList()
                            .forEach { stopSubscription(it.first, it.second) }
                        colorCapabilities.remove(nodeId)
                        colorLifetimes.remove(nodeId)
                        colorSubscriptionTokens.remove(nodeId)
                        colorSubscriptionPaths.remove(nodeId)
                        electricalSubscriptionPaths.remove(nodeId)
                        sensorReadTokens.remove(nodeId)
                        sensorSubscriptionPaths.remove(nodeId)
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

    private fun readDeviceTypes(nodeId: Long, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            var finished = false
            fun finish(value: Map<String, List<Long>>?, error: String?) {
                runOnUiThread {
                    if (!finished) {
                        finished = true
                        if (error == null) result.success(value)
                        else result.error("matter_descriptor_failed", error, null)
                    }
                }
            }
            controller.readPath(
                object : ReportCallback {
                    override fun onError(attributePath: ChipAttributePath?, eventPath: ChipEventPath?, ex: Exception) {
                        finish(null, ex.message ?: "Descriptor read failed")
                    }
                    override fun onReport(nodeState: NodeState) {
                        try {
                            val types = mutableMapOf<String, List<Long>>()
                            for ((endpoint, state) in nodeState.endpointStates) {
                                val tlv = state.getClusterState(0x001DL)?.getAttributeState(0L)?.tlv ?: continue
                                val reader = TlvReader(tlv)
                                val ids = mutableListOf<Long>()
                                reader.enterArray(AnonymousTag)
                                while (!reader.isEndOfContainer()) {
                                    reader.enterStructure(AnonymousTag)
                                    ids.add(reader.getUInt(ContextSpecificTag(0)).toLong())
                                    reader.getUShort(ContextSpecificTag(1))
                                    reader.exitContainer()
                                }
                                reader.exitContainer()
                                types[endpoint.toString()] = ids
                            }
                            finish(types, null)
                        } catch (error: Exception) {
                            finish(null, error.message ?: "Invalid Descriptor")
                        }
                    }
                }, devicePointer,
                listOf(ChipAttributePath.newInstance(
                    ChipPathId.forWildcard(), ChipPathId.forId(0x001DL), ChipPathId.forId(0L),
                )), null, false, 0,
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

    private fun stopSubscription(nodeId: Long, kind: String) {
        val key = nodeId to kind
        subscriptionEpochs.remove(key)
        subscriptionIds.remove(key)?.let { id ->
            try { controller.shutdownSubscriptions(controller.fabricIndex, nodeId, id) }
            catch (error: Exception) { Log.w(TAG, "Subscription cleanup failed", error) }
        }
    }

    private fun startSubscription(nodeId: Long, kind: String): Any {
        stopSubscription(nodeId, kind)
        return Any().also { subscriptionEpochs[nodeId to kind] = it }
    }

    private fun rememberSubscription(nodeId: Long, kind: String, token: Any, id: Long) {
        runOnUiThread {
            if (subscriptionEpochs[nodeId to kind] === token) {
                subscriptionIds[nodeId to kind] = id
            } else {
                try { controller.shutdownSubscriptions(controller.fabricIndex, nodeId, id) }
                catch (error: Exception) { Log.w(TAG, "Late subscription cleanup failed", error) }
            }
        }
    }

    override fun onDestroy() {
        eventSink = null
        levelEventSink = null
        colorEventSink = null
        electricalEventSink = null
        sensorEventSink = null
        sensorReadTokens.clear()
        sensorSubscriptionPaths.clear()
        sensorHandler.removeCallbacksAndMessages(null)
        subscriptionEpochs.keys.toList().forEach { stopSubscription(it.first, it.second) }
        colorLifetimes.clear()
        colorSubscriptionTokens.clear()
        colorSubscriptionPaths.clear()
        electricalSubscriptionPaths.clear()
        super.onDestroy()
    }

    private fun decodeColors(nodeState: NodeState): Map<Int, Map<String, Int?>> {
        val colors = mutableMapOf<Int, Map<String, Int?>>()
        for ((endpoint, state) in nodeState.endpointStates) {
            if (endpoint <= 0) continue
            val cluster = state.getClusterState(COLOR_CLUSTER) ?: continue
            val values = mutableMapOf<String, Int?>()
            for ((attribute, name) in COLOR_ATTRIBUTES) {
                val tlv = cluster.getAttributeState(attribute)?.tlv ?: continue
                val reader = TlvReader(tlv)
                values[name] = if (reader.isNull()) {
                    reader.getNull(AnonymousTag)
                    null
                } else if (attribute == 3L || attribute == 4L ||
                    attribute == 0x4000L || attribute == 0x400AL) {
                    reader.getUShort(AnonymousTag).toInt()
                } else {
                    reader.getUByte(AnonymousTag).toInt()
                }
            }
            if (values.isNotEmpty()) colors[endpoint] = values
        }
        return colors
    }

    private fun readColors(nodeId: Long, result: MethodChannel.Result) {
        val lifetime = colorLifetimes.getOrPut(nodeId) { Any() }
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        withConnectedDevice(nodeId, result) { devicePointer ->
            controller.readPath(object : ReportCallback {
                override fun onError(attributePath: ChipAttributePath?, eventPath: ChipEventPath?, ex: Exception) {
                    if (replied.compareAndSet(false, true)) {
                        runOnUiThread { result.error("matter_color_read_failed", ex.message, null) }
                    }
                }
                override fun onReport(nodeState: NodeState) {
                    if (!replied.compareAndSet(false, true)) return
                    try {
                        val all = decodeColors(nodeState)
                        val colors = all.filterValues { ((it["capabilities"] ?: 0) and 9) != 0 }
                        runOnUiThread {
                            if (colorLifetimes[nodeId] !== lifetime || pendingRemovals.contains(nodeId)) {
                                result.error("device_removed", "Color read belongs to an old device", null)
                                return@runOnUiThread
                            }
                            colorCapabilities[nodeId] = colors.mapValues { it.value["capabilities"]!! }
                            result.success(colors.mapKeys { it.key.toString() })
                            // Subscribe only to attributes actually returned by this device.
                            val paths = colors.flatMap { (endpoint, values) ->
                                COLOR_ATTRIBUTES.filterValues { values.containsKey(it) }.keys
                                    .map { endpoint to it }
                            }.sortedWith(compareBy({ it.first }, { it.second }))
                            if (paths.isNotEmpty() && colorSubscriptionPaths[nodeId] != paths) {
                                try { subscribeColors(nodeId, devicePointer, paths) }
                                catch (error: Exception) {
                                    colorSubscriptionPaths.remove(nodeId)
                                    colorSubscriptionTokens.remove(nodeId)
                                    Log.e(TAG, "Color subscription setup failed", error)
                                }
                            } else if (paths.isEmpty()) {
                                stopSubscription(nodeId, "color")
                                colorSubscriptionTokens.remove(nodeId)
                                colorSubscriptionPaths.remove(nodeId)
                            }
                        }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("matter_color_read_failed", error.message, null) }
                    }
                }
            }, devicePointer, COLOR_ATTRIBUTES.keys.map { attribute ->
                ChipAttributePath.newInstance(ChipPathId.forWildcard(),
                    ChipPathId.forId(COLOR_CLUSTER), ChipPathId.forId(attribute))
            }, null, false, 0)
        }
    }

    private fun invokeColor(nodeId: Long, endpoint: Int, mode: String,
        first: Int, second: Int, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            val writer = TlvWriter()
            writer.startStructure(AnonymousTag)
            if (mode == "hs") {
                writer.put(ContextSpecificTag(0), first.toUByte())
                writer.put(ContextSpecificTag(1), second.toUByte())
            } else {
                writer.put(ContextSpecificTag(0), first.toUShort())
                writer.put(ContextSpecificTag(1), second.toUShort())
            }
            writer.put(ContextSpecificTag(2), 0.toUShort()) // immediate; read back final color
            // ExecuteIfOff allows configuring the indicator without changing OnOff or level.
            writer.put(ContextSpecificTag(3), 1.toUByte())
            writer.put(ContextSpecificTag(4), 1.toUByte())
            writer.endStructure()
            val invoke = InvokeElement.newInstance(endpoint, COLOR_CLUSTER,
                if (mode == "hs") 0x06L else 0x07L, writer.getEncoded(), null)
            controller.invoke(object : InvokeCallback {
                override fun onError(ex: Exception?) {
                    result.error("matter_color_invoke_failed", ex?.message, null)
                }
                override fun onResponse(invokeElement: InvokeElement?, successCode: Long) {
                    if (successCode == STATUS_OK) result.success(null)
                    else result.error("matter_color_invoke_failed", "Color command rejected", successCode)
                }
            }, devicePointer, invoke, 0, 0)
        }
    }

    private fun subscribeColors(nodeId: Long, devicePointer: Long, paths: List<Pair<Int, Long>>) {
        val token = startSubscription(nodeId, "color")
        colorSubscriptionTokens[nodeId] = token
        colorSubscriptionPaths[nodeId] = paths
        fun stale() {
            runOnUiThread {
                if (colorSubscriptionTokens[nodeId] !== token) return@runOnUiThread
                for (endpoint in paths.map { it.first }.distinct()) {
                    colorEventSink?.success(mapOf("nodeId" to nodeId, "endpoint" to endpoint,
                        "stale" to true, "values" to emptyMap<String, Int>()))
                }
            }
        }
        controller.subscribeToPath(
            SubscriptionEstablishedCallback { id -> rememberSubscription(nodeId, "color", token, id) },
            ResubscriptionAttemptCallback { _, _ -> stale() },
            object : ReportCallback {
                override fun onError(attributePath: ChipAttributePath?, eventPath: ChipEventPath?, ex: Exception) {
                    stale()
                    runOnUiThread {
                        if (colorSubscriptionTokens[nodeId] === token) {
                            colorSubscriptionPaths.remove(nodeId)
                            colorSubscriptionTokens.remove(nodeId)
                        }
                    }
                }
                override fun onReport(nodeState: NodeState) {
                    try {
                        val colors = decodeColors(nodeState)
                        runOnUiThread {
                            if (colorSubscriptionTokens[nodeId] !== token || pendingRemovals.contains(nodeId)) return@runOnUiThread
                            for ((endpoint, values) in colors) {
                                if (colorCapabilities[nodeId]?.containsKey(endpoint) != true) continue
                                colorEventSink?.success(mapOf("nodeId" to nodeId,
                                    "endpoint" to endpoint, "values" to values))
                            }
                        }
                    } catch (error: Exception) {
                        Log.e(TAG, "Invalid color report", error)
                        stale()
                    }
                }
            }, devicePointer, paths.map { (endpoint, attribute) ->
                ChipAttributePath.newInstance(endpoint, COLOR_CLUSTER, attribute)
            }, null, 1, 60, true, false, 0)
    }

    private fun readLevels(nodeId: Long, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            controller.readPath(
                object : ReportCallback {
                    override fun onError(attributePath: ChipAttributePath?, eventPath: ChipEventPath?, ex: Exception) {
                        result.error("matter_level_read_failed", ex.message, null)
                    }

                    override fun onReport(nodeState: NodeState) {
                        try {
                            val levels = mutableMapOf<String, Int?>()
                            for ((endpoint, state) in nodeState.endpointStates) {
                                if (endpoint <= 0) continue
                                val tlv = state.getClusterState(0x0008L)
                                    ?.getAttributeState(0L)?.tlv ?: continue
                                val reader = TlvReader(tlv)
                                levels[endpoint.toString()] = if (reader.isNull()) {
                                    reader.getNull(AnonymousTag)
                                    null
                                } else {
                                    reader.getUByte(AnonymousTag).toInt()
                                }
                            }
                            val endpoints = levels.keys.map(String::toInt).sorted()
                            result.success(levels)
                            if (endpoints.isNotEmpty() &&
                                levelSubscriptionEndpoints[nodeId] != endpoints) {
                                try {
                                    subscribeLevels(nodeId, devicePointer, endpoints)
                                    levelSubscriptionEndpoints[nodeId] = endpoints
                                } catch (error: Exception) {
                                    Log.e(TAG, "LevelControl subscription setup failed", error)
                                }
                            }
                        } catch (error: Exception) {
                            result.error("matter_level_read_failed", error.message, null)
                        }
                    }
                },
                devicePointer,
                listOf(ChipAttributePath.newInstance(
                    ChipPathId.forWildcard(), ChipPathId.forId(0x0008L), ChipPathId.forId(0L),
                )), null, false, 0,
            )
        }
    }

    private fun invokeLevel(nodeId: Long, endpoint: Int, level: Int, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            val writer = TlvWriter()
            writer.startStructure(AnonymousTag)
            writer.put(ContextSpecificTag(0), level.toUByte())
            writer.put(ContextSpecificTag(2), 0.toUByte())
            writer.put(ContextSpecificTag(3), 0.toUByte())
            writer.endStructure()
            val invoke = InvokeElement.newInstance(
                endpoint, 0x0008L, 0x04L, writer.getEncoded(), null,
            )
            controller.invoke(
                object : InvokeCallback {
                    override fun onError(ex: Exception?) {
                        result.error("matter_level_invoke_failed", ex?.message ?: "Level command failed", null)
                    }

                    override fun onResponse(invokeElement: InvokeElement?, successCode: Long) {
                        if (successCode == STATUS_OK) result.success(null)
                        else result.error("matter_level_invoke_failed", "Level command returned error", successCode)
                    }
                }, devicePointer, invoke, 0, 0,
            )
        }
    }

    private fun contactSensorEndpoints(nodeState: NodeState): Set<Int> {
        val endpoints = mutableSetOf<Int>()
        for ((endpoint, state) in nodeState.endpointStates) {
            // BooleanState also belongs to other device types. Never infer a door
            // from that cluster alone or from an old cached device label.
            if (endpoint !in 1..65534 || state.getClusterState(0x0045L) == null) continue
            val tlv = state.getClusterState(0x001DL)?.getAttributeState(0L)?.tlv ?: continue
            try {
                val reader = TlvReader(tlv)
                val types = mutableSetOf<Long>()
                reader.enterArray(AnonymousTag)
                while (!reader.isEndOfContainer()) {
                    reader.enterStructure(AnonymousTag)
                    types.add(reader.getUInt(ContextSpecificTag(0)).toLong())
                    reader.getUShort(ContextSpecificTag(1))
                    reader.exitContainer()
                }
                reader.exitContainer()
                if (ManisaSensorCodec.CONTACT_DEVICE_TYPE in types) endpoints.add(endpoint)
            } catch (error: Exception) {
                Log.w(TAG, "Contact type not confirmed on endpoint=$endpoint", error)
            }
        }
        return endpoints
    }

    private fun decodeSensorMeasurements(nodeState: NodeState,
        contacts: Set<Int> = contactSensorEndpoints(nodeState)): Map<Int, Map<String, Any?>> {
        val readings = mutableMapOf<Int, Map<String, Any?>>()
        for ((endpoint, state) in nodeState.endpointStates) {
            if (endpoint !in 1..65534) continue
            val values = mutableMapOf<String, Any?>()
            for ((cluster, attribute, _) in SENSOR_ATTRIBUTES) {
                if (cluster == 0x0045L && endpoint !in contacts) continue
                val tlv = state.getClusterState(cluster)?.getAttributeState(attribute)?.tlv ?: continue
                val reader = TlvReader(tlv)
                val raw: Any? = if (reader.isNull()) {
                    reader.getNull(AnonymousTag)
                    null
                } else when (cluster) {
                    0x0402L -> reader.getShort(AnonymousTag).toInt()
                    0x0405L -> reader.getUShort(AnonymousTag).toInt()
                    0x0406L -> reader.getUByte(AnonymousTag).toInt()
                    0x0045L -> reader.getBool(AnonymousTag)
                    else -> continue
                }
                val types = if (endpoint in contacts) setOf(ManisaSensorCodec.CONTACT_DEVICE_TYPE)
                    else emptySet()
                ManisaSensorCodec.decode(cluster, raw, types)?.let { (name, value) -> values[name] = value }
            }
            if (values.isNotEmpty()) readings[endpoint] = values
        }
        return readings
    }

    private fun readSensorMeasurements(nodeId: Long, result: MethodChannel.Result) {
        val token = Any()
        sensorReadTokens[nodeId] = token
        var completed = false // Read callbacks and connection callbacks are serialized on main.
        fun active() = sensorReadTokens[nodeId] === token && !pendingRemovals.contains(nodeId)
        val timeout = Runnable {
            if (!completed && sensorReadTokens[nodeId] === token) {
                completed = true
                sensorReadTokens.remove(nodeId)
                result.error("matter_sensor_timeout", "Sensor read timed out", null)
            }
        }
        sensorHandler.postDelayed(timeout, 14000)
        fun fail(message: String?) {
            runOnUiThread {
                if (completed || !active()) return@runOnUiThread
                completed = true
                sensorHandler.removeCallbacks(timeout)
                sensorReadTokens.remove(nodeId)
                result.error("matter_sensor_read_failed", message, null)
            }
        }
        val connectionResult = object : MethodChannel.Result {
            override fun success(result: Any?) { }
            override fun error(code: String, message: String?, details: Any?) = fail(message)
            override fun notImplemented() = fail("Sensor read unavailable")
        }
        try {
            withConnectedDevice(nodeId, connectionResult) { devicePointer ->
                runOnUiThread {
                    if (completed || !active()) return@runOnUiThread
                    try {
                        controller.readPath(object : ReportCallback {
                            override fun onError(attributePath: ChipAttributePath?,
                                eventPath: ChipEventPath?, ex: Exception) = fail(ex.message)
                            override fun onReport(nodeState: NodeState) {
                                runOnUiThread {
                                    if (completed || !active()) return@runOnUiThread
                                    val readings = try { decodeSensorMeasurements(nodeState) }
                                        catch (error: Exception) { fail(error.message); return@runOnUiThread }
                                    completed = true
                                    sensorHandler.removeCallbacks(timeout)
                                    sensorReadTokens.remove(nodeId)
                                    result.success(readings.mapKeys { it.key.toString() })
                                    val paths = readings.flatMap { (endpoint, values) ->
                                        SENSOR_ATTRIBUTES.filter { values.containsKey(it.third) }
                                            .map { Triple(endpoint, it.first, it.second) }
                                    }.sortedWith(compareBy({ it.first }, { it.second }, { it.third }))
                                    if (paths.isEmpty()) {
                                        stopSubscription(nodeId, "sensors")
                                        sensorSubscriptionPaths.remove(nodeId)
                                    } else if (sensorSubscriptionPaths[nodeId] != paths) {
                                        subscribeSensorMeasurements(nodeId, devicePointer, paths)
                                    }
                                }
                            }
                        }, devicePointer, SENSOR_ATTRIBUTES.map { (cluster, attribute, _) ->
                            ChipAttributePath.newInstance(ChipPathId.forWildcard(),
                                ChipPathId.forId(cluster), ChipPathId.forId(attribute))
                        } + listOf(ChipAttributePath.newInstance(ChipPathId.forWildcard(),
                            ChipPathId.forId(0x001DL), ChipPathId.forId(0L))), null, false, 0)
                    } catch (error: Exception) { fail(error.message) }
                }
            }
        } catch (error: Exception) { fail(error.message) }
    }

    private fun subscribeSensorMeasurements(nodeId: Long, devicePointer: Long,
        paths: List<Triple<Int, Long, Long>>) {
        val token = startSubscription(nodeId, "sensors")
        sensorSubscriptionPaths[nodeId] = paths
        fun markStale() {
            runOnUiThread {
                if (subscriptionEpochs[nodeId to "sensors"] !== token ||
                    pendingRemovals.contains(nodeId)) return@runOnUiThread
                for ((endpoint, endpointPaths) in paths.groupBy { it.first }) {
                    val names = endpointPaths.mapNotNull { path ->
                        SENSOR_ATTRIBUTES.firstOrNull {
                            it.first == path.second && it.second == path.third
                        }?.third
                    }
                    sensorEventSink?.success(mapOf("nodeId" to nodeId,
                        "endpoint" to endpoint, "staleMetrics" to names))
                }
            }
        }
        fun terminate() {
            runOnUiThread {
                if (subscriptionEpochs[nodeId to "sensors"] !== token) return@runOnUiThread
                markStale()
                stopSubscription(nodeId, "sensors")
                sensorSubscriptionPaths.remove(nodeId)
            }
        }
        try {
            controller.subscribeToPath(
                SubscriptionEstablishedCallback { id -> rememberSubscription(nodeId, "sensors", token, id) },
                ResubscriptionAttemptCallback { _, _ -> markStale() },
                object : ReportCallback {
                    override fun onError(attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?, ex: Exception) {
                        Log.w(TAG, "Sensor subscription failed", ex)
                        terminate()
                    }
                    override fun onReport(nodeState: NodeState) {
                        runOnUiThread {
                            if (subscriptionEpochs[nodeId to "sensors"] !== token ||
                                pendingRemovals.contains(nodeId)) return@runOnUiThread
                            try {
                                val contacts = paths.filter { it.second == 0x0045L }.map { it.first }.toSet()
                                for ((endpoint, values) in decodeSensorMeasurements(nodeState, contacts)) {
                                    val supported = paths.filter { it.first == endpoint }.map { it.second }.toSet()
                                    val filtered = values.filterKeys { name ->
                                        SENSOR_ATTRIBUTES.any { it.third == name && it.first in supported }
                                    }
                                    if (filtered.isNotEmpty()) sensorEventSink?.success(mapOf(
                                        "nodeId" to nodeId, "endpoint" to endpoint, "values" to filtered))
                                }
                            } catch (error: Exception) {
                                Log.w(TAG, "Invalid sensor report", error)
                                markStale()
                            }
                        }
                    }
                }, devicePointer, paths.map { (endpoint, cluster, attribute) ->
                    ChipAttributePath.newInstance(endpoint, cluster, attribute)
                }, null, if (paths.any { it.second == 0x0406L || it.second == 0x0045L }) 1 else 5,
                60, true, false, 0,
            )
        } catch (error: Exception) {
            Log.w(TAG, "Sensor subscription setup failed", error)
            terminate()
        }
    }

    private fun decodeElectricalMeasurements(
        nodeState: NodeState,
    ): Map<Int, Map<String, Long?>> {
        fun nullableLong(tlv: ByteArray): Long? {
            val reader = TlvReader(tlv)
            return if (reader.isNull()) {
                reader.getNull(AnonymousTag)
                null
            } else {
                reader.getLong(AnonymousTag)
            }
        }

        fun nullableEnergy(tlv: ByteArray): Long? {
            val reader = TlvReader(tlv)
            if (reader.isNull()) {
                reader.getNull(AnonymousTag)
                return null
            }
            reader.enterStructure(AnonymousTag)
            return reader.getLong(ContextSpecificTag(0))
        }

        val measurements = mutableMapOf<Int, Map<String, Long?>>()
        for ((endpoint, state) in nodeState.endpointStates) {
            if (endpoint <= 0) continue
            val values = mutableMapOf<String, Long?>()
            for ((cluster, attribute, name) in ELECTRICAL_ATTRIBUTES) {
                val tlv = state.getClusterState(cluster)
                    ?.getAttributeState(attribute)?.tlv ?: continue
                values[name] = if (cluster == 0x0091L) {
                    nullableEnergy(tlv)
                } else {
                    nullableLong(tlv)
                }
            }
            if (values.isNotEmpty()) measurements[endpoint] = values
        }
        return measurements
    }

    private fun readElectricalMeasurements(nodeId: Long, result: MethodChannel.Result) {
        withConnectedDevice(nodeId, result) { devicePointer ->
            controller.readPath(
                object : ReportCallback {
                    override fun onError(
                        attributePath: ChipAttributePath?,
                        eventPath: ChipEventPath?,
                        ex: Exception,
                    ) {
                        result.error("matter_electrical_read_failed", ex.message, null)
                    }

                    override fun onReport(nodeState: NodeState) {
                        try {
                            val measurements = decodeElectricalMeasurements(nodeState)
                            result.success(measurements.mapKeys { it.key.toString() })
                            val paths = measurements.flatMap { (endpoint, values) ->
                                ELECTRICAL_ATTRIBUTES
                                    .filter { values.containsKey(it.third) }
                                    .map { Triple(endpoint, it.first, it.second) }
                            }.sortedWith(compareBy({ it.first }, { it.second }, { it.third }))
                            if (paths.isNotEmpty() &&
                                electricalSubscriptionPaths[nodeId] != paths) {
                                try {
                                    subscribeElectricalMeasurements(nodeId, devicePointer, paths)
                                } catch (error: Exception) {
                                    electricalSubscriptionPaths.remove(nodeId)
                                    Log.e(TAG, "Electrical subscription setup failed", error)
                                }
                            } else if (paths.isEmpty()) {
                                stopSubscription(nodeId, "electrical")
                                electricalSubscriptionPaths.remove(nodeId)
                            }
                        } catch (error: Exception) {
                            result.error(
                                "matter_electrical_read_failed",
                                error.message ?: "Invalid electrical measurement",
                                null,
                            )
                        }
                    }
                },
                devicePointer,
                ELECTRICAL_ATTRIBUTES.map { (cluster, attribute, _) ->
                    ChipAttributePath.newInstance(
                        ChipPathId.forWildcard(),
                        ChipPathId.forId(cluster),
                        ChipPathId.forId(attribute),
                    )
                },
                null,
                false,
                0,
            )
        }
    }

    private fun subscribeElectricalMeasurements(
        nodeId: Long,
        devicePointer: Long,
        paths: List<Triple<Int, Long, Long>>,
    ) {
        val token = startSubscription(nodeId, "electrical")
        electricalSubscriptionPaths[nodeId] = paths

        fun markStale() {
            runOnUiThread {
                if (subscriptionEpochs[nodeId to "electrical"] !== token) {
                    return@runOnUiThread
                }
                val byEndpoint = paths.groupBy { it.first }
                for ((endpoint, endpointPaths) in byEndpoint) {
                    val names = endpointPaths.mapNotNull { path ->
                        ELECTRICAL_ATTRIBUTES.firstOrNull {
                            it.first == path.second && it.second == path.third
                        }?.third
                    }
                    electricalEventSink?.success(
                        mapOf(
                            "nodeId" to nodeId,
                            "endpoint" to endpoint,
                            "staleMetrics" to names,
                        ),
                    )
                }
            }
        }

        controller.subscribeToPath(
            SubscriptionEstablishedCallback { id ->
                rememberSubscription(nodeId, "electrical", token, id)
            },
            ResubscriptionAttemptCallback { cause, delayMs ->
                Log.w(TAG, "Electrical resubscribe cause=$cause delayMs=$delayMs")
                markStale()
            },
            object : ReportCallback {
                override fun onError(
                    attributePath: ChipAttributePath?,
                    eventPath: ChipEventPath?,
                    ex: Exception,
                ) {
                    markStale()
                    runOnUiThread {
                        if (subscriptionEpochs[nodeId to "electrical"] === token) {
                            electricalSubscriptionPaths.remove(nodeId)
                            stopSubscription(nodeId, "electrical")
                        }
                    }
                    Log.e(TAG, "Electrical subscription failed", ex)
                }

                override fun onReport(nodeState: NodeState) {
                    try {
                        val measurements = decodeElectricalMeasurements(nodeState)
                        runOnUiThread {
                            if (subscriptionEpochs[nodeId to "electrical"] !== token ||
                                pendingRemovals.contains(nodeId)) return@runOnUiThread
                            for ((endpoint, values) in measurements) {
                                if (paths.none { it.first == endpoint }) continue
                                electricalEventSink?.success(
                                    mapOf(
                                        "nodeId" to nodeId,
                                        "endpoint" to endpoint,
                                        "values" to values,
                                    ),
                                )
                            }
                        }
                    } catch (error: Exception) {
                        Log.e(TAG, "Invalid electrical report", error)
                        markStale()
                    }
                }
            },
            devicePointer,
            paths.map { (endpoint, cluster, attribute) ->
                ChipAttributePath.newInstance(endpoint, cluster, attribute)
            },
            null,
            1,
            60,
            true,
            false,
            0,
        )
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
        if (onOffSubscriptionEndpoints[nodeId] == endpoints) return
        val token = startSubscription(nodeId, "onoff")
        val paths = endpoints.map { endpoint ->
            ChipAttributePath.newInstance(
                endpoint,
                OnOff.ID,
                OnOff.Attribute.OnOff.id,
            )
        }
        controller.subscribeToPath(
            SubscriptionEstablishedCallback { subscriptionId ->
                rememberSubscription(nodeId, "onoff", token, subscriptionId)
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
                    runOnUiThread {
                        if (subscriptionEpochs[nodeId to "onoff"] === token) {
                            onOffSubscriptionEndpoints.remove(nodeId)
                            stopSubscription(nodeId, "onoff")
                        }
                    }
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
                            if (subscriptionEpochs[nodeId to "onoff"] !== token) return@runOnUiThread
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
            true, // Keep OnOff, LevelControl and ColorControl subscriptions together.
            false,
            0,
        )
        onOffSubscriptionEndpoints[nodeId] = endpoints
    }

    private fun subscribeLevels(nodeId: Long, devicePointer: Long, endpoints: List<Int>) {
        val token = startSubscription(nodeId, "level")
        val paths = endpoints.map { endpoint ->
            ChipAttributePath.newInstance(endpoint, 0x0008L, 0L)
        }
        controller.subscribeToPath(
            SubscriptionEstablishedCallback { subscriptionId ->
                rememberSubscription(nodeId, "level", token, subscriptionId)
            },
            ResubscriptionAttemptCallback { cause, delayMs ->
                Log.w(TAG, "LevelControl resubscribe cause=$cause delayMs=$delayMs")
            },
            object : ReportCallback {
                override fun onError(
                    attributePath: ChipAttributePath?,
                    eventPath: ChipEventPath?,
                    ex: Exception,
                ) {
                    runOnUiThread {
                        if (subscriptionEpochs[nodeId to "level"] === token) {
                            levelSubscriptionEndpoints.remove(nodeId)
                            stopSubscription(nodeId, "level")
                        }
                    }
                    Log.e(TAG, "LevelControl subscription failed", ex)
                }

                override fun onReport(nodeState: NodeState) {
                    for (endpoint in endpoints) {
                        val tlv = nodeState.getEndpointState(endpoint)
                            ?.getClusterState(0x0008L)
                            ?.getAttributeState(0L)?.tlv ?: continue
                        try {
                            val reader = TlvReader(tlv)
                            val level = if (reader.isNull()) {
                                reader.getNull(AnonymousTag)
                                null
                            } else {
                                reader.getUByte(AnonymousTag).toInt()
                            }
                            runOnUiThread {
                                if (subscriptionEpochs[nodeId to "level"] !== token) return@runOnUiThread
                                levelEventSink?.success(mapOf(
                                    "nodeId" to nodeId,
                                    "endpoint" to endpoint,
                                    "level" to level,
                                ))
                            }
                        } catch (error: Exception) {
                            Log.e(TAG, "Invalid LevelControl report", error)
                        }
                    }
                }
            },
            devicePointer,
            paths,
            null,
            1,
            60,
            true, // Keep OnOff, LevelControl and ColorControl subscriptions together.
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
