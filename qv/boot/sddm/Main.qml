import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#090909"

  property string currentUser: userModel.lastUser
  property real unit: Math.max(1, Math.min(width / 1920, height / 1080))
  property color textColor: "#d0d0d0"
  property color mutedColor: "#808080"
  property color panelColor: "#101010"
  property color borderColor: "#303030"
  property color focusBorderColor: "#505050"
  property color accentColor: "#b01616"

  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.color: "#101010"
    border.width: Math.max(1, Math.round(root.unit))
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      errorMessage.text = "ACCESS DENIED"
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      errorMessage.text = ""
    }
  }

  Column {
    id: loginBox
    anchors.centerIn: parent
    spacing: Math.round(34 * root.unit)
    width: Math.min(parent.width * 0.82, Math.round(620 * root.unit))

    Image {
      source: "logo.png"
      width: Math.min(loginBox.width * 0.9, Math.round(560 * root.unit))
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : Math.round(220 * root.unit)
      fillMode: Image.PreserveAspectFit
      opacity: 0.86
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(loginBox.width, Math.round(420 * root.unit))
      spacing: Math.round(12 * root.unit)

      Rectangle {
        width: parent.width
        height: Math.round(46 * root.unit)
        radius: 0
        color: root.panelColor
        border.color: password.activeFocus ? root.focusBorderColor : root.borderColor
        border.width: Math.max(1, Math.round(root.unit))
        clip: true

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: Math.round(16 * root.unit)
          anchors.rightMargin: Math.round(16 * root.unit)
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          passwordCharacter: "\u2022"
          color: root.textColor
          selectedTextColor: "#090909"
          selectionColor: "#303030"
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: Math.round(18 * root.unit)
          font.letterSpacing: Math.round(1 * root.unit)
          focus: true

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            }
          }
        }
      }

      Text {
        id: errorMessage
        text: ""
        color: root.accentColor
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Math.round(14 * root.unit)
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.round(24 * root.unit)
    spacing: Math.round(18 * root.unit)

    Text {
      text: "REBOOT"
      color: rebootMouse.containsMouse ? root.accentColor : root.mutedColor
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Math.round(13 * root.unit)
      MouseArea {
        id: rebootMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: sddm.reboot()
      }
    }

    Text {
      text: "POWER"
      color: powerMouse.containsMouse ? root.accentColor : root.mutedColor
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Math.round(13 * root.unit)
      MouseArea {
        id: powerMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: sddm.powerOff()
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
