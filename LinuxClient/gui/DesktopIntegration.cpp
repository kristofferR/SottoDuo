#include "DesktopIntegration.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
const QByteArray marker = "# Managed by Sotto\n";

QString quotedExecutable(QString path) {
  // Desktop Exec quoting, followed by the desktop-entry string escaping.
  path.replace('%', "%%");
  path.replace('\\', "\\\\");
  path.replace('"', "\\\"");
  path.replace('`', "\\`");
  path.replace('$', "\\$");
  path.replace('\\', "\\\\");
  return '"' + path + '"';
}
} // namespace

DesktopIntegration::DesktopIntegration(bool preview, QObject *parent)
    : QObject(parent), m_preview(preview) {}

QString DesktopIntegration::entryPath() const {
  return QStandardPaths::writableLocation(
             QStandardPaths::GenericConfigLocation) +
         "/autostart/org.sotto.Gui.desktop";
}

bool DesktopIntegration::launchAtLogin() const {
  if (m_preview)
    return false;
  QFile entry(entryPath());
  if (!entry.open(QIODevice::ReadOnly))
    return false;
  const auto data = entry.readAll();
  return data.startsWith(marker) && data.contains("\nHidden=false\n");
}

void DesktopIntegration::setLaunchAtLogin(bool enabled) {
  m_error.clear();
  auto fail = [this](const QString &message) {
    m_error = message;
    emit changed();
  };
  if (m_preview) {
    fail("Login startup cannot be changed in preview mode.");
    return;
  }
  QFile existing(entryPath());
  if (existing.exists() && (!existing.open(QIODevice::ReadOnly) ||
                            !existing.readAll().startsWith(marker))) {
    fail("An existing login entry is managed outside Sotto. Update it in your "
         "desktop’s startup settings.");
    return;
  }
  existing.close();

  // Preserve a launcher's stable symlink path across application updates.
  const QString argument = QCoreApplication::arguments().first();
  const QString executable = argument.contains('/')
                                 ? QFileInfo(argument).absoluteFilePath()
                                 : QStandardPaths::findExecutable(argument);
  if (enabled &&
      (executable.isEmpty() || executable.contains(QChar('\n')) ||
       executable.contains(QChar('\r')) || executable.contains(QChar('\t')) ||
       executable.contains('=') || !QFileInfo(executable).isExecutable())) {
    fail("Launch Sotto from its installed application before enabling login "
         "startup.");
    return;
  }
  const QByteArray data =
      marker + "[Desktop Entry]\n" +
      (enabled
           ? QByteArray(
                 "Type=Application\nName=Sotto\n"
                 "Comment=Keep dictation feedback available\nIcon=sotto\n"
                 "Terminal=false\nHidden=false\n") +
                 ("Exec=" + quotedExecutable(executable) + " --background\n")
                     .toUtf8()
           : QByteArray("Hidden=true\n"));
  if (!QDir().mkpath(QFileInfo(entryPath()).absolutePath())) {
    fail("Couldn’t create the login startup folder. Check its permissions.");
    return;
  }
  QSaveFile output(entryPath());
  if (!output.open(QIODevice::WriteOnly) || output.write(data) != data.size() ||
      !output.commit()) {
    fail("Couldn’t save login startup. Check the permissions of your startup "
         "folder.");
    return;
  }
  emit changed();
}
