#include "Bridge.h"
#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QIcon>
#include <QMenu>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSystemTrayIcon>
#include <QTimer>

int main(int argc, char **argv) {
  QApplication app(argc, argv);
  app.setOrganizationName("Sotto");
  app.setApplicationName("Sotto");
  app.setDesktopFileName("sotto");
  QCommandLineParser parser;
  parser.setApplicationDescription("Sotto for Linux");
  parser.addHelpOption();
  parser.addOption(
      {"preview", "Show sample data without connecting to a client."});
  parser.addOption(
      {"theme", "Preview appearance: system, light, dark or omarchy.", "name"});
  parser.addOption({"capture",
                    "Save preview screenshots and exit (requires --preview).",
                    "directory"});
  parser.process(app);
  const bool preview = parser.isSet("preview");
  if (parser.isSet("capture") && !preview)
    return 2;
  QQuickStyle::setStyle("Basic");
  Bridge bridge(preview);
  if (parser.isSet("theme"))
    bridge.setTheme(parser.value("theme"));
  QQmlApplicationEngine engine;
  engine.rootContext()->setContextProperty("bridge", &bridge);
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
  engine.loadFromModule("Sotto", "Main");
  if (engine.rootObjects().isEmpty())
    return 1;
  auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
  if (!window)
    return 1;
  QSystemTrayIcon tray(QIcon(":/qt/qml/Sotto/mark.svg"));
  QMenu menu;
  auto show = [window] {
    window->show();
    window->raise();
    window->requestActivate();
  };
  menu.addAction("Open Sotto", &app, show);
  menu.addAction("Quit Sotto window (background dictation stays running)", &app,
                 [window, &app] {
                   if (window->close())
                     app.quit();
                 });
  tray.setToolTip("Sotto");
  tray.setContextMenu(&menu);
  QObject::connect(&tray, &QSystemTrayIcon::activated, &app,
                   [show](QSystemTrayIcon::ActivationReason reason) {
                     if (reason == QSystemTrayIcon::Trigger)
                       show();
                   });
  if (!preview && QSystemTrayIcon::isSystemTrayAvailable()) {
    app.setQuitOnLastWindowClosed(false);
    tray.show();
  }
  if (parser.isSet("capture")) {
    const QString directory = parser.value("capture");
    QDir().mkpath(directory);
    auto *timer = new QTimer(&app);
    auto page = std::make_shared<int>(-1);
    auto success = std::make_shared<bool>(true);
    QObject::connect(
        timer, &QTimer::timeout, &app, [&, timer, page, success, directory] {
          if (*page >= 0)
            *success = window->grabWindow().save(
                           directory + QString("/page-%1.png").arg(*page)) &&
                       *success;
          ++*page;
          if (*page == 5) {
            timer->stop();
            app.exit(*success ? 0 : 1);
            return;
          }
          window->setProperty("page", *page);
        });
    timer->start(400);
  }
  return app.exec();
}
