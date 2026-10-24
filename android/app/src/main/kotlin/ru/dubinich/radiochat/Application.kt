package ru.dubinich.radiochat

import io.flutter.app.FlutterApplication
import ru.rustore.sdk.pushclient.RuStorePushClient
import ru.rustore.sdk.pushclient.common.logger.DefaultLogger

class Application : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        RuStorePushClient.init(
            this,
            projectId = "-eqBiu-NvdfINsGbS8JyTUdcRgUXvrfo",
            logger = DefaultLogger(),
        )
    }
}