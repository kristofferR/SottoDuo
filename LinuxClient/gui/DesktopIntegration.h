#pragma once
#include <QObject>
class QProcess;

class DesktopIntegration : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool launchAtLogin READ launchAtLogin NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
  Q_PROPERTY(QString clientService READ clientService NOTIFY changed)
  Q_PROPERTY(bool clientServiceBusy READ clientServiceBusy NOTIFY changed)
public:
  explicit DesktopIntegration(bool preview, QObject *parent = nullptr,
                              const QString &clientExecutable = {});
  bool launchAtLogin() const;
  QString error() const { return m_error; }
  QString clientService() const { return m_clientService; }
  bool clientServiceBusy() const { return m_clientServiceBusy; }
  Q_INVOKABLE void setLaunchAtLogin(bool enabled);
  Q_INVOKABLE void refreshClientService();
  Q_INVOKABLE void setUpClientService();
  Q_INVOKABLE void quit() { emit quitRequested(); }
signals:
  void changed();
  void quitRequested();

private:
  QString entryPath() const;
  QString servicePath() const;
  bool m_preview;
  QString m_clientExecutable;
  QString m_clientService;
  bool m_clientServiceBusy = false;
  unsigned m_serviceRefresh = 0;
  QString m_error;
};
