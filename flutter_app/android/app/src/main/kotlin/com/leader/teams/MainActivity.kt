package com.leader.teams

import android.os.Build
import android.view.Display
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * Hosts the Flutter engine and answers the app's display channel.
 *
 * The channel exists so the "Frame Rate" setting can use the platform's own
 * refresh-rate APIs instead of faking a frame rate in Dart. Nothing here
 * drops, delays or skips a frame: it reports the display modes the panel
 * really has and, when asked, sets the window's preferred mode. The
 * compositor schedules frames exactly as it already did.
 *
 * Only `WindowManager.LayoutParams.preferredDisplayModeId` (API 23) and
 * `preferredRefreshRate` (API 21) are used, so this compiles and behaves the
 * same on every SDK the app supports. A rate the panel has no mode for is
 * therefore *not* offered to the user at all — see `availableFrameRates` in
 * `frame_rate.dart`. Advertising 30fps on a 60Hz panel would mean throwing
 * frames away, which is the one thing this must not do.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "setFrameRate" -> {
                val hz = call.argument<Number>("hz")?.toFloat()
                result.success(setFrameRate(hz))
            }
            else -> result.notImplemented()
        }
    }

    /**
     * The refresh rates the panel supports at the resolution it is running
     * now. Modes at another resolution are excluded deliberately — switching
     * resolution to chase a refresh rate is not what the user asked for.
     */
    private fun capabilities(): Map<String, Any?> {
        val display = currentDisplay()
        val rates = supportedRates(display)
        return mapOf(
            "supportedRates" to rates,
            "activeRate" to display?.refreshRate?.toDouble(),
            // A choice is only real when there is more than one mode to
            // choose between.
            "canSelectMode" to (rates.size > 1),
            // No honest hint API at this SDK floor: a rate without a mode
            // could only be reached by dropping frames.
            "supportsFrameRateHint" to false
        )
    }

    private fun supportedRates(display: Display?): List<Double> {
        if (display == null) return emptyList()
        val active = display.mode ?: return listOf(display.refreshRate.toDouble())
        return display.supportedModes
            .filter {
                it.physicalWidth == active.physicalWidth &&
                    it.physicalHeight == active.physicalHeight
            }
            .map { it.refreshRate.toDouble() }
            .distinctBy { Math.round(it * 10.0) }
            .sorted()
    }

    /**
     * Asks the window for the mode closest to [hz], or hands the display
     * back to the system when it is null. Returns the rate that was really
     * requested so Dart can report the truth rather than the intention.
     */
    private fun setFrameRate(hz: Float?): Double? {
        val display = currentDisplay()

        if (hz == null) {
            runOnUiThread {
                window.attributes = window.attributes.apply {
                    preferredDisplayModeId = 0
                    preferredRefreshRate = 0f
                }
            }
            return null
        }

        val active = display?.mode
        val match = display?.supportedModes
            ?.filter {
                active == null ||
                    (it.physicalWidth == active.physicalWidth &&
                        it.physicalHeight == active.physicalHeight)
            }
            ?.minByOrNull { abs(it.refreshRate - hz) }
            ?: return null

        runOnUiThread {
            window.attributes = window.attributes.apply {
                preferredDisplayModeId = match.modeId
                preferredRefreshRate = match.refreshRate
            }
        }
        return match.refreshRate.toDouble()
    }

    private fun currentDisplay(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

    private companion object {
        const val CHANNEL = "mtm/display"
    }
}
