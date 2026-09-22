import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("外观")
        icon: "preferences-desktop-theme"
        source: "configAppearance.qml"
    }
    ConfigCategory {
        name: i18n("倒计时")
        icon: "chronometer"
        source: "configCountdown.qml"
    }
    ConfigCategory {
        name: i18n("学期周数")
        icon: "view-calendar"
        source: "configGeneral.qml"
    }
}
