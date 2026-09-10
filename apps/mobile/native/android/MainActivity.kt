package com.manisa.manisa_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ClusterIDMapping.OnOff
import chip.devicecontroller.CommissionParameters
import chip.devicecontroller.ControllerParams
import chip.devicecontroller.GetConnectedDeviceCallbackJni.GetConnectedDeviceCallback
import chip.devicecontroller.InvokeCallback
import chip.devicecontroller.NetworkCredentials
import chip.devicecontroller.ReportCallback
import chip.devicecontroller.ResubscriptionAttemptCallback
import chip.devicecontroller.SubscriptionEstablishedCallback
import chip.devicecontroller.model.ChipAttributePath
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
import matter.tlv.AnonymousTag
import matter.tlv.TlvReader
import matter.tlv.TlvWriter

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "ManisaMatter"
        private const val METHODS = "com.manisa/matter/methods"
        private const val EVENTS = "com.manisa/matter/events"
        private const val VENDOR_ID = 0xFFF4
        private const val STATUS_OK = 0L
        private const val PERMISSION_REQUEST_MATTER = 9101
    }

    private data class CommissionRequest(
        val setupPayload: String,
        val ssid: String,
        val password: String,
        val result: MethodChannel.Result,
    )

    private lateinit var platform: AndroidChipPlatform
    private lateinit var controller: ChipDeviceController
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
        initializeMatter()
    }

    private fun initializeMatter() {
        ChipDeviceController.loadJni()
        platform = AndroidChipPlatform(
            AndroidBleManager(this),
            AndroidNfcCommissioningManager(),
            PreferencesKeyValueStoreManager(this),
            PreferencesConfigurationManager(this),
            NsdManagerServiceResolver(
                this,
                NsdManagerServiceResolver.NsdManagerResolverAvailState(),
            ),
            NsdManagerServiceBrowser(this),
            ChipMdnsCallbackImpl(),
            DiagnosticDataProviderImpl(this),
        )
        controller = ChipDeviceController(
            ControllerParams.newBuilder()
                .setControllerVendorId(VENDOR_ID)
                .setEnableServerInteractions(true)
                .build(),
        )
        controller.setCompletionListener(commissioningListener)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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
                    controller.unpairDevice(nodeId)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            Log.e(TAG, "Matter method ${call.method} failed", error)
            result.error("matter_exception", error.message, null)
        }
    }

    private fun commissionWifi(call: MethodCall, result: MethodChannel.Result) {
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
        if (!setupPayload.startsWith("MT:") || ssid.isEmpty()) {
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
        val nodeId = nextNodeId()
        val network = NetworkCredentials.forWiFi(
            NetworkCredentials.WiFiCredentials(request.ssid, request.password),
        )
        val params = CommissionParameters.Builder()
            .setNetworkCredentials(network)
            .build()

        pendingCommission = request.result
        pendingCommissionNodeId = nodeId
        controller.setCompletionListener(commissioningListener)
        controller.pairDeviceWithCode(
            nodeId,
            request.setupPayload,
            true,
            false,
            params,
        )
    }

    private val commissioningListener = object : GenericChipDeviceListener() {
        override fun onCommissioningComplete(nodeId: Long, errorCode: Long) {
            val pending = pendingCommission ?: return
            if (nodeId != pendingCommissionNodeId) return
            if (errorCode != STATUS_OK) {
                pendingCommission = null
                pendingCommissionNodeId = 0
                pending.error("commissioning_failed", "Matter commissioning failed", errorCode)
                return
            }
            discoverOnOffEndpoints(
                nodeId,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val endpoints = result as? List<*> ?: emptyList<Any>()
                        pendingCommission = null
                        pendingCommissionNodeId = 0
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
                        pending.error(errorCode, errorMessage, errorDetails)
                    }

                    override fun notImplemented() {
                        pendingCommission = null
                        pendingCommissionNodeId = 0
                        pending.notImplemented()
                    }
                },
                subscribe = true,
            )
        }

        override fun onError(error: Throwable?) {
            val pending = pendingCommission ?: return
            pendingCommission = null
            pendingCommissionNodeId = 0
            pending.error(
                "commissioning_error",
                error?.message ?: "Matter commissioning error",
                null,
            )
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
                null,
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
