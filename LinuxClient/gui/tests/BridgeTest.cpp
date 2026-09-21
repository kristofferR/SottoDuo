#include "../Bridge.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class BridgeTest : public QObject {
  Q_OBJECT
private slots:
  void themeFollowsPaletteAndRecovers() {
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    qputenv("XDG_STATE_HOME", directory.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", directory.path().toUtf8());
    const QString path = directory.path() + "/omarchy/current/theme";
    QVERIFY(QDir().mkpath(path));
    auto write = [&path](const QByteArray &colors) {
      QFile file(path + "/colors.toml");
      QVERIFY(file.open(QIODevice::WriteOnly));
      QCOMPARE(file.write(colors), colors.size());
    };
    write("background = \"#101913\"\nforeground = \"#a1af9c\"\naccent = "
          "\"#4a9a68\"\n");
    Bridge bridge(true);
    bridge.setTheme("omarchy");
    QCOMPARE(bridge.colors()["canvas"].toString(), "#101913");
    QCOMPARE(bridge.colors()["accent"].toString(), "#4a9a68");
    write(
        "background = '#ffffff'\nforeground = '#111111'\naccent = '#0000aa'\n");
    QTRY_COMPARE_WITH_TIMEOUT(bridge.colors()["canvas"].toString(),
                              QString("#ffffff"), 4500);
    // A missing theme uses an explicit fallback and recovers when it returns.
    QVERIFY(QFile::remove(path + "/colors.toml"));
    bridge.setTheme("omarchy");
    QCOMPARE(bridge.colors()["canvas"].toString(), "#1b252e");
    QVERIFY(bridge.themeNote().contains("unavailable"));
    bridge.setTheme("light");
    QCOMPARE(bridge.colors()["canvas"].toString(), "#f8f6f2");
  }
  void privateSocketReceivesStructuredSnapshot() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    QByteArray input;
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
        input += socket->readAll();
        if (input.endsWith('\n'))
          socket->write("{\"ok\":true,\"data\":{\"version\":1,\"activity\":{"
                        "\"phase\":\"recording\"},\"busy\":true}}\n");
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QCOMPARE(QJsonDocument::fromJson(input).object()["action"].toString(),
             "snapshot");
    QCOMPARE(bridge.snapshot()["activity"].toMap()["phase"].toString(),
             "recording");
    server.close();
    QTRY_VERIFY_WITH_TIMEOUT(!bridge.connected(), 2500);
    QVERIFY(bridge.snapshot().isEmpty());
  }
  void pagesRenderAndOverlayCannotTakeFocus() {
    QQuickStyle::setStyle("Basic");
    Bridge bridge(true);
    bridge.setTheme("dark");
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    auto *hud = window->findChild<QQuickWindow *>("dictationHud");
    QVERIFY(hud);
    QVERIFY(!hud->transientParent());
    QVERIFY(hud->flags().testFlag(Qt::WindowDoesNotAcceptFocus));
    QVERIFY(hud->flags().testFlag(Qt::WindowTransparentForInput));
    for (int page = 0; page < 5; ++page) {
      QVERIFY(window->setProperty("page", page));
      QTest::qWait(50);
      QVERIFY(!window->grabWindow().isNull());
    }
    QCOMPARE(warnings.count(), 0);
    QVERIFY(!hud->isVisible());
  }
};
QTEST_MAIN(BridgeTest)
#include "BridgeTest.moc"
