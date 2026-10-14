import QtQuick 2.5
import QtQuick.Window 2.2
import QtQuick.Controls 2.5
import net.asivery.AppLoad 1.0
import net.asivery.Framebuffer 1.0

Rectangle {
    id: _appLoadView
    anchors.fill: parent
    color: "#f0f0f0"

    property var windowArchetype: Qt.createComponent("window.qml")
    property var absoluteRoot: _appLoadView
    property var virtualKeyboardRef: null

    readonly property int minimumResolutionWidth: 400

    signal requestClose

    AppLoadLibrary {
        id: library
    }

    // The open folder ("" for the top level). Apps name their folder in their
    // manifest ("folder": "Games"); folders are listed first, then the apps
    // without one.
    property string folder: ""
    readonly property var entries: {
        const apps = [];
        for(let app of library.applications) apps.push(app);
        if(folder !== "") {
            return apps.filter(app => app.folder === folder).map(app => ({ app: app, name: app.name }));
        }
        const folders = {};
        const loose = [];
        for(let app of apps) {
            if(app.folder === "") {
                loose.push({ app: app, name: app.name });
            } else {
                (folders[app.folder] = folders[app.folder] || []).push(app.icon);
            }
        }
        const names = Object.keys(folders).sort((a, b) => a.localeCompare(b));
        return names.map(name => ({ folder: name, name: name, icons: folders[name].slice(0, 4) })).concat(loose);
    }
    // A folder that disappeared (after a reload): back to the top
    onEntriesChanged: if(folder !== "" && entries.length === 0) folder = ""
    function getResolutionOf(device) {
        switch(device) {
            case "original": return [1620, 2160];
            case "move": return [954, 1696];
        }
    }

    function launchWindow(modelData, extraArgs, extraEnv) {
        let qtfbKey = -1;
        let win;

        if(modelData.externalType === 2 /* EXTERNAL_QTFB */) {
            qtfbKey = Math.floor(Math.random() * 10000000);
        }
        if(modelData.externalType != 1 /* EXTERNAL_NOGUI */) {
            /* Create a new window*/
            if(library.isFrontendRunningFor(modelData.id) && !modelData.canHaveMultipleFrontends) {
                console.log("Cannot load multiple frontends for app. It doesn't support it.");
                return;
            }
            if(windowArchetype.status !== Component.Ready) {
                console.log("Window object not ready: " + windowArchetype.status);
                console.log(windowArchetype.errorString());
                return;
            }
            win = windowArchetype.createObject(absoluteRoot, { x: 100, y: 100 });
            if(win == null) {
                console.log("Failed to instantiate a window object!");
                return;
            }

            win.appName = modelData.name;
            win.supportsScaling = modelData.supportsScaling;
            win.supportsRotation = modelData.supportsRotation;
            win.virtualKeyboardLayout = modelData.virtualKeyboardLayout;
            win.disablesWindowedMode = modelData.disablesWindowedMode;

            win.virtualKeyboardRef = _appLoadView.virtualKeyboardRef;

            win.globalWidth = Qt.binding(function() { return _appLoadView.width; })
            win.globalHeight = Qt.binding(function() { return _appLoadView.height; })
            const deviceAspectRatio = _appLoadView.width < _appLoadView.height ? (_appLoadView.width / _appLoadView.height) : (_appLoadView.height / _appLoadView.width);
            const deviceWidth = Math.min(_appLoadView.height, _appLoadView.width);
            const realAspectRatio = modelData.aspectRatio || deviceAspectRatio;
            const width = modelData.width || deviceWidth;
            console.log(`Application starting on device with ${deviceAspectRatio} aspect ratio. Real aspect ratio of the application is going to be ${realAspectRatio}`);
            [win.minWidth, win.minHeight] = [win.implicitWidth, win.implicitHeight] = [minimumResolutionWidth, Math.floor(minimumResolutionWidth / realAspectRatio)];
            [win.scaledContentWidth, win.scaledContentHeight] = [width, Math.floor(width / realAspectRatio)];
            // The original width / height is bound to scaled globalWidth. This needs to be flipped if the device is on its side:
            if(_appLoadView.width > _appLoadView.height) {
                [win.width, win._height] = [win._height, win.width];
            }

            win.qtfbKey = qtfbKey;
            if(qtfbKey != -1) {
                win.windowCanvas.forceActiveFocus();
            }
            win.closed.connect(() => {
                win.destroy();
                if(_appLoadView.virtualKeyboardRef.active && _appLoadView.virtualKeyboardRef.config === win.keyboardConfig) {
                    _appLoadView.virtualKeyboardRef.active = false;
                }
            });
        }

        if(modelData.externalType == 0 /* INTERNAL */) {
            win.loadApplication(modelData.id);
        } else if(modelData.externalType == 1 /* EXTERNAL_NOGUI */ || modelData.externalType == 2 /* EXTERNAL_QTFB */) {
            win.appPid = library.launchExternal(modelData.id, qtfbKey, extraArgs || [], extraEnv || {});
        }

        return win;
    }


    Connections {
        target: AppLoadLauncher
        function onRequestLaunch(id, args, env, windowed) {
            for(let i of library.applications) {
                if(i.id === id) {
                    console.log("Launching: " + id);
                    const window = launchWindow(i, args, env);
                    if(i.disablesWindowedMode || !windowed) window.maximize();
                    return;
                }
            }
            console.log(`No application installed with id: ${id}`);
        }
    }

    Rectangle {
        anchors.fill: parent
        MouseArea {
            // Eat the events.
            anchors.fill: parent
        }

        Rectangle {
            id: header
            anchors.top: parent.top
            width: parent.width
            height: 100

            Rectangle {
                anchors.topMargin: 25
                anchors.leftMargin: 25
                anchors.top: parent.top
                anchors.left: parent.left
                height: 60
                width: 250

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        if(_appLoadView.folder !== "") {
                            _appLoadView.folder = "";
                        } else {
                            _appLoadView.requestClose();
                        }
                    }
                }

                Image {
                    id: arrowBack
                    source: "qrc:/appload/icons/exit"
                    sourceSize.width: 60
                    sourceSize.height: 60
                    anchors.left: parent.left
                }
                Text {
                    anchors.left: arrowBack.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pointSize: 24
                    text: qsTr("Back")
                }
            }

            Rectangle {
                id: refreshButton
                anchors.topMargin: 25
                anchors.rightMargin: 25
                anchors.top: parent.top
                anchors.right: parent.right
                height: 60
                width: 250
                property string reloadIconSource: "qrc:/appload/icons/reload"

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        library.reloadList();
                        refreshButton.reloadIconSource = "qrc:/appload/icons/check";
                        reloadIconSwitchBackTimer.start();
                    }
                }

                Timer {
                    id: reloadIconSwitchBackTimer
                    interval: 1000
                    onTriggered: () => refreshButton.reloadIconSource = "qrc:/appload/icons/reload"
                }

                Image {
                    id: reloadIcon
                    source: refreshButton.reloadIconSource
                    sourceSize.width: 60
                    sourceSize.height: 60
                    anchors.right: parent.right
                }
                Text {
                    anchors.right: reloadIcon.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pointSize: 24
                    text: qsTr("Reload")
                }
            }

            Text {
                anchors.fill: parent
                text: _appLoadView.folder || "AppLoad"
                font.pointSize: 40
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        GridView {
            anchors.top: header.bottom
            anchors.topMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.floor((parent.width - 20) / cellWidth) * cellWidth
            height: parent.height - 100
            id: gridView
            model: _appLoadView.entries
            cellWidth: 200 + 20
            cellHeight: 200 + 20
            interactive: false

            delegate: Rectangle {
                required property var modelData
                anchors.margins: 10
                width: gridView.cellWidth - 20
                height: gridView.cellHeight - 20

                Image {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.margins: 10
                    id: appIcon
                    visible: !modelData.folder
                    source: modelData.folder ? "" : modelData.app.icon
                    width: 150
                    height: 150
                }

                // A folder: a frame with the icons of its first apps
                Rectangle {
                    anchors.fill: appIcon
                    visible: !!modelData.folder
                    radius: 20
                    color: "transparent"
                    border.width: 4
                    border.color: "black"

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 8
                        Repeater {
                            model: modelData.folder ? modelData.icons : []
                            Image {
                                required property var modelData
                                source: modelData
                                width: 56
                                height: 56
                            }
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: appIcon.bottom
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    anchors.topMargin: 5
                    text: modelData.name
                    font.pointSize: 24
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        if(modelData.folder) {
                            _appLoadView.folder = modelData.folder;
                            return;
                        }
                        launchWindow(modelData.app).maximize();
                    }
                    onPressAndHold: () => {
                        if(modelData.folder) {
                            _appLoadView.folder = modelData.folder;
                            return;
                        }
                        const window = launchWindow(modelData.app);
                        if(modelData.app.disablesWindowedMode) {
                            window.maximize();
                        }
                    }
                }
            }
        }
    }
}
