#include "DesktopIntegration.h"
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
const QByteArray marker = "# Managed by Sotto\n";
const QByteArray serviceMarker = "# Managed by Sotto Linux GUI\n";

struct ServiceUnit {
  bool available = false;
  QString loadState;
  QString fragment;
};

ServiceUnit serviceUnit() {
  QProcess process;
  process.start("systemctl", {"--user", "show", "--property=LoadState",
                               "--property=FragmentPath", "sotto-client.service"});
  if (!process.waitForStarted(1000) || !process.waitForFinished(1500)) {
    process.kill();
    process.waitForFinished(1000);
    return {};
  }
  if (process.exitCode() != 0)
    return {};
  ServiceUnit unit;
  unit.available = true;
  for (const auto &line : process.readAllStandardOutput().split('\n')) {
    if (line.startsWith("LoadState="))
      unit.loadState = QString::fromUtf8(line.mid(10));
    else if (line.startsWith("FragmentPath="))
      unit.fragment = QString::fromUtf8(line.mid(13));
  }
  return unit;
}

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
QString quotedServiceExecutable(QString path) {
  path.replace('%', "%%");
  path.replace('$', "$$");
  path.replace('\\', "\\\\");
  path.replace('"', "\\\"");
  return '"' + path + '"';
}
} // namespace

DesktopIntegration::DesktopIntegration(bool preview, QObject *parent,
                                       const QString &clientExecutable)
    : QObject(parent), m_preview(preview),
      m_clientExecutable(clientExecutable.isEmpty()
                             ? QCoreApplication::applicationDirPath() + "/sotto"
                             : clientExecutable) {}

QString DesktopIntegration::entryPath() const {
  return QStandardPaths::writableLocation(
             QStandardPaths::GenericConfigLocation) +
         "/autostart/org.sotto.Gui.desktop";
}

QString DesktopIntegration::servicePath() const {
  return QStandardPaths::writableLocation(
             QStandardPaths::GenericConfigLocation) +
         "/systemd/user/sotto-client.service";
}

void DesktopIntegration::refreshClientService() {
  if (m_preview)
    return;
  QProcess check;
  check.start("systemctl", {"--user", "is-active", "sotto-client.service"});
  if (!check.waitForStarted(1000) || !check.waitForFinished(1500)) {
    check.kill();
    check.waitForFinished(1000);
    m_clientService = "Systemd user service unavailable";
  } else if (check.exitCode() == 0 &&
             check.readAllStandardOutput().trimmed() == "active") {
    m_clientService = "Running";
  } else {
    const auto unit = serviceUnit();
    m_clientService = !unit.available ? "Systemd user service unavailable"
                      : unit.loadState == "not-found" ? "Not installed"
                      : "Stopped";
  }
  emit changed();
}

void DesktopIntegration::setUpClientService() {
  if (m_preview || m_clientServiceBusy)
    return;
  m_error.clear();
  auto fail = [this](const QString &message) {
    m_error = message;
    m_clientServiceBusy = false;
    refreshClientService();
  };
  const QString path = servicePath();
  QFileInfo unit(path);
  const auto loaded = serviceUnit();
  if (!loaded.available) {
    fail("Couldn’t inspect the background service. Check your user service manager.");
    return;
  }
  if (loaded.loadState != "not-found" &&
      (loaded.fragment.isEmpty() ||
       QFileInfo(loaded.fragment).absoluteFilePath() != unit.absoluteFilePath())) {
    fail("An existing background service is managed outside Sotto. Update it through your desktop setup.");
    return;
  }
  bool created = false;
  if (unit.isSymLink()) {
    fail("The background service is a symlink. Manage it through your desktop setup.");
    return;
  }
  {
    QFile existing(path);
    QByteArray previous;
    if (unit.exists()) {
      if (!existing.open(QIODevice::ReadOnly) ||
          !(previous = existing.readAll()).startsWith(serviceMarker)) {
        fail("An existing background service is managed outside Sotto. Update it through your desktop setup.");
        return;
      }
    }
    const QFileInfo executable(m_clientExecutable);
    if (!executable.isFile() || !executable.isExecutable() ||
        m_clientExecutable.contains(QChar('\n')) ||
        m_clientExecutable.contains(QChar('\r'))) {
      fail("Install the Sotto background client beside this GUI, then try again.");
      return;
    }
    const QByteArray data =
        serviceMarker +
        ("[Unit]\nDescription=Sotto desktop dictation client\n"
         "PartOf=graphical-session.target\nAfter=graphical-session.target\n\n"
         "[Service]\nType=simple\nExecStart=" +
         quotedServiceExecutable(executable.absoluteFilePath()) +
         " daemon\nRestart=on-failure\nRestartSec=3\nUMask=0077\n"
         "NoNewPrivileges=yes\n\n[Install]\n"
         "WantedBy=graphical-session.target\n")
            .toUtf8();
    if (previous != data) {
      if (!QDir().mkpath(unit.absolutePath())) {
        fail("Couldn’t create the background-service folder.");
        return;
      }
      QSaveFile output(path);
      if (!output.open(QIODevice::WriteOnly) || output.write(data) != data.size() ||
          !output.commit()) {
        fail("Couldn’t install the background service. Check the folder permissions.");
        return;
      }
      created = true;
    }
  }
  m_clientServiceBusy = true;
  m_clientService = "Starting…";
  emit changed();
  auto *process = new QProcess(this);
  connect(process, &QProcess::errorOccurred, this,
          [fail, process](QProcess::ProcessError) {
            fail("Couldn’t run the background service manager.");
            process->deleteLater();
          });
  connect(process, &QProcess::finished, this,
          [this, process, fail, created](int code, QProcess::ExitStatus status) {
            if (!m_clientServiceBusy)
              return;
            if (status != QProcess::NormalExit || code != 0) {
              fail("Couldn’t start background dictation. Check your user service status.");
              process->deleteLater();
              return;
            }
            if (created && process->property("reloaded").isNull()) {
              process->setProperty("reloaded", true);
              process->start("systemctl", {"--user", "enable", "--now",
                                          "sotto-client.service"});
              return;
            }
            m_clientServiceBusy = false;
            refreshClientService();
            process->deleteLater();
          });
  process->start("systemctl", created
                                  ? QStringList{"--user", "daemon-reload"}
                                  : QStringList{"--user", "enable", "--now",
                                                "sotto-client.service"});
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
