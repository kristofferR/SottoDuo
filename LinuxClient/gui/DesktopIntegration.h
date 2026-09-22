#pragma once
#include <QObject>

class DesktopIntegration : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool launchAtLogin READ launchAtLogin NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
public:
  explicit DesktopIntegration(bool preview, QObject *parent = nullptr);
  bool launchAtLogin() const;
  QString error() const { return m_error; }
  Q_INVOKABLE void setLaunchAtLogin(bool enabled);
  Q_INVOKABLE void quit() { emit quitRequested(); }
signals:
  void changed();
  void quitRequested();

private:
  QString entryPath() const;
  bool m_preview;
  QString m_error;
};
