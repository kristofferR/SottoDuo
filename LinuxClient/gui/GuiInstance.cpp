#include "GuiInstance.h"
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>

GuiInstance::~GuiInstance() {
  if (m_primary) {
    auto bus = QDBusConnection::sessionBus();
    bus.unregisterService("org.sotto.Gui");
    bus.unregisterObject("/Sotto");
  }
}

GuiInstance::Result GuiInstance::acquire(bool background) {
  auto bus = QDBusConnection::sessionBus();
  if (!bus.isConnected() ||
      !bus.registerObject("/Sotto", this,
                          QDBusConnection::ExportScriptableSlots)) {
    m_error = "Couldn’t connect Sotto to the desktop session bus.";
    return Result::Failed;
  }
  if (bus.registerService("org.sotto.Gui")) {
    m_primary = true;
    return Result::Primary;
  }
  const QDBusReply<bool> registered =
      bus.interface()->isServiceRegistered("org.sotto.Gui");
  if (!registered.isValid() || !registered.value()) {
    m_error = "Couldn’t register Sotto in this desktop session.";
    return Result::Failed;
  }
  if (!background) {
    const auto request = QDBusMessage::createMethodCall(
        "org.sotto.Gui", "/Sotto", "org.sotto.Gui", "Show");
    if (bus.call(request, QDBus::Block, 5000).type() ==
        QDBusMessage::ErrorMessage) {
      m_error =
          "Sotto is already running but didn’t respond. Try opening it again.";
      return Result::Failed;
    }
  }
  return Result::Forwarded;
}
