package com.manisa.manisa_mobile

import chip.devicecontroller.ChipDeviceController
import chip.devicecontroller.ICDDeviceInfo

open class GenericChipDeviceListener : ChipDeviceController.CompletionListener {
    override fun onConnectDeviceComplete() = Unit
    override fun onStatusUpdate(status: Int) = Unit
    override fun onPairingComplete(code: Long) = Unit
    override fun onPairingDeleted(code: Long) = Unit
    override fun onCommissioningComplete(nodeId: Long, errorCode: Long) = Unit

    override fun onReadCommissioningInfo(
        vendorId: Int,
        productId: Int,
        wifiEndpointId: Int,
        threadEndpointId: Int,
    ) = Unit

    override fun onCommissioningStatusUpdate(nodeId: Long, stage: String, errorCode: Long) = Unit
    override fun onCommissioningStageStart(nodeId: Long, stage: String) = Unit
    override fun onNotifyChipConnectionClosed() = Unit
    override fun onCloseBleComplete() = Unit
    override fun onError(error: Throwable?) = Unit
    override fun onOpCSRGenerationComplete(csr: ByteArray) = Unit
    override fun onICDRegistrationInfoRequired() = Unit
    override fun onICDRegistrationComplete(errorCode: Long, icdDeviceInfo: ICDDeviceInfo) = Unit
}
