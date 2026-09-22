#include "../Bridge.h"
#include "../HudSurface.h"
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

class BridgeTest : public QObject {
  Q_OBJECT
private slots:
  void initTestCase() {
    QQuickStyle::setStyle("Basic");
    qmlRegisterSingletonType<HudSurface>(
        "Sotto.Native", 1, 0, "HudSurface",
        [](QQmlEngine *, QJSEngine *) -> QObject * { return new HudSurface; });
  }
  void waylandOverlayLifecycle() {
    if (!qEnvironmentVariableIsSet("SOTTO_GUI_TEST_WAYLAND"))
      QSKIP("Opt-in compositor test; run this slot alone on Wayland.");
    QVERIFY(QGuiApplication::platformName().startsWith("wayland"));
    Bridge bridge(true);
    QQmlEngine engine;
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QQmlComponent model(&engine);
    model.setData(R"(
      import QtQml
      QtObject {
        property bool visible: false
        property bool active: false
        property bool busy: false
        property var activity: ({ phase: "idle", source: "No microphone in use" })
        property var feedback: ({})
        property string limitNotice: ""
        function duration(seconds) { return "0:00"; }
        property var c: bridge.colors
        function messageFor(phase) { return "Dictation preview"; }
      }
    )",
                  QUrl());
    QScopedPointer<QObject> ui(model.create());
    QVERIFY2(ui, qPrintable(model.errorString()));
    QQmlComponent component(
        &engine, QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Hud.qml"));
    QScopedPointer<QObject> object(component.createWithInitialProperties(
        {{"ui", QVariant::fromValue(ui.data())}}));
    QVERIFY2(object, qPrintable(component.errorString()));
    auto *hud = qobject_cast<QQuickWindow *>(object.data());
    QVERIFY(hud);
    for (int cycle = 0; cycle < 2; ++cycle) {
      hud->show();
      QVERIFY(QTest::qWaitForWindowExposed(hud));
      QTest::qWait(2000);
      QVERIFY(!hud->isActive());
      const QString capture = qEnvironmentVariable("SOTTO_GUI_TEST_CAPTURE");
      if (!capture.isEmpty())
        QVERIFY(hud->grabWindow().save(capture));
      hud->hide();
      QTest::qWait(500);
    }
    QCOMPARE(warnings.count(), 0);
  }
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
    QCOMPARE(bridge.connectionStatus(), "unavailable");
  }
  void offlinePagesShareOneConnectionNotice() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    qputenv("SOTTO_CLIENT_CONFIG",
            (directory.path() + "/client.json").toUtf8());
    Bridge bridge(false);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QTRY_COMPARE(bridge.connectionStatus(), QString("setupRequired"));
    auto *banner = window->findChild<QQuickItem *>("connectionBanner");
    auto *notice = window->findChild<QQuickItem *>("actionNotice");
    QVERIFY(banner && notice);
    QVERIFY(banner->isVisible());
    for (const int page : {1, 3, 0}) {
      window->setProperty("page", page);
      QTest::qWait(50);
      QVERIFY(!notice->isVisible());
      QVERIFY(window->property("notice").toString().isEmpty());
    }
    auto *key = window->findChild<QQuickItem *>("shortcutKeycap");
    QVERIFY(key && key->isVisible());
    QVERIFY(key->width() > 0 && key->height() > 0);
    QVERIFY(!window->property("sourcesChecked").toBool());
    const QString capture = qEnvironmentVariable("SOTTO_GUI_TEST_CAPTURE");
    if (!capture.isEmpty())
      QVERIFY(window->grabWindow().save(capture));
    QFile config(qEnvironmentVariable("SOTTO_CLIENT_CONFIG"));
    QVERIFY(config.open(QIODevice::WriteOnly));
    config.close();
    bridge.request("snapshot");
    QTRY_COMPARE(bridge.connectionStatus(), QString("unavailable"));
    QVERIFY(banner->isVisible());
    QVERIFY(!notice->isVisible());
    QCOMPARE(warnings.count(), 0);
    qunsetenv("SOTTO_CLIENT_CONFIG");
  }
  void djiSettingsGuardDestinationAndRetainSaveErrors() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [socket] {
        if (!socket->canReadLine())
          return;
        socket->readLine();
        socket->write("{\"ok\":true,\"data\":{\"version\":1}}\n");
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QQmlEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    QQmlComponent model(&engine);
    model.setData(R"(
      import QtQml
      QtObject {
        property var snapshot: ({ buttonEnabled: true, buttonSettingsSupported: true,
          button: { available: true, selectedHere: false } })
        property bool busy: false
        property var c: bridge.colors
      }
    )",
                  QUrl());
    QScopedPointer<QObject> ui(model.create());
    QVERIFY2(ui, qPrintable(model.errorString()));
    QQmlComponent component(
        &engine,
        QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/DjiSettings.qml"));
    QScopedPointer<QObject> settings(component.createWithInitialProperties(
        {{"ui", QVariant::fromValue(ui.data())}}));
    QVERIFY2(settings, qPrintable(component.errorString()));
    auto *select = settings->findChild<QQuickItem *>("djiSelectButton");
    auto *deselect = settings->findChild<QQuickItem *>("djiDeselectButton");
    auto *receiving = settings->findChild<QQuickItem *>("djiEnabledSwitch");
    QVERIFY(select && deselect && receiving);
    QVERIFY(select->isEnabled());
    QVERIFY(!deselect->isEnabled());
    QVERIFY(receiving->isEnabled());
    ui->setProperty("busy", true);
    QVERIFY(!select->isEnabled());
    QVERIFY(!deselect->isEnabled());
    QVERIFY(!receiving->isEnabled());
    ui->setProperty("busy", false);
    auto state = ui->property("snapshot").value<QJSValue>().toVariant().toMap();
    state["button"] = QVariantMap{{"available", false}, {"selectedHere", true}};
    ui->setProperty("snapshot", state);
    QVERIFY(!select->isEnabled());
    QVERIFY(deselect->isEnabled());
    state["buttonEnabled"] = false;
    ui->setProperty("snapshot", state);
    QVERIFY(!deselect->isEnabled());
    emit bridge.failed("saveButton", "Cannot save settings");
    emit bridge.reply("receiver", QVariantMap{{"available", true}});
    auto *error = settings->findChild<QQuickItem *>("djiSettingsError");
    QVERIFY(error);
    QCOMPARE(error->property("text").toString(), "Cannot save settings");
    QCOMPARE(warnings.count(), 0);
  }
  void pagesRenderAndOverlayCannotTakeFocus() {
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
    const QString djiCapture = qEnvironmentVariable("SOTTO_GUI_DJI_CAPTURE");
    if (!djiCapture.isEmpty()) {
      auto *dji = window->findChild<QQuickItem *>("djiSettings");
      QVERIFY(dji);
      for (auto *parent = dji->parentItem(); parent;
           parent = parent->parentItem()) {
        if (parent->property("contentY").isValid()) {
          parent->setProperty("contentY",
                              dji->mapToItem(parent, QPointF()).y() +
                                  parent->property("contentY").toReal());
          break;
        }
      }
      QTest::qWait(50);
      QVERIFY(window->grabWindow().save(djiCapture));
    }
    auto *login = window->findChild<QQuickItem *>("launchAtLoginSwitch");
    QVERIFY(login);
    QVERIFY(!login->isEnabled());
    for (auto *parent = login->parentItem(); parent;
         parent = parent->parentItem()) {
      if (parent->property("contentY").isValid()) {
        parent->setProperty("contentY",
                            parent->property("contentHeight").toReal() -
                                parent->height());
        break;
      }
    }
    QTest::qWait(50);
    const QString capture = qEnvironmentVariable("SOTTO_GUI_SETTINGS_CAPTURE");
    if (!capture.isEmpty())
      QVERIFY(window->grabWindow().save(capture));
    QCOMPARE(warnings.count(), 0);
    QVERIFY(!hud->isVisible());
  }
  void settingsCanStartHiddenAndCloseWithoutAbandoningTest() {
    Bridge bridge(true);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.setInitialProperties({{"startHidden", true}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QVERIFY(!window->isVisible());
    window->show();
    QVERIFY(window->isVisible());
    window->setProperty("busy", true);
    window->setProperty(
        "activity", QVariantMap{{"phase", "recording"}, {"trigger", "test"}});
    QVERIFY(!window->close());
    QVERIFY(window->isVisible());
    QVERIFY(!window->property("notice").toString().isEmpty());
    window->setProperty("busy", false);
    QVERIFY(window->close());
    QVERIFY(!window->isVisible());
    window->show();
    QVERIFY(window->isVisible());
    QCOMPARE(warnings.count(), 0);
  }
  void liveFeedbackShowsTimePartialTextAndLimitWithoutActivatingOverlay() {
    Bridge bridge(true);
    bridge.setTheme("dark");
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QVariantMap feedback{
        {"elapsedSeconds", 145},
        {"remainingSeconds", 27},
        {"partialText", "A provisional sentence"},
        {"streamAvailable", true},
        {"levels", QVariantList{0.05, 0.2, 0.5, 0.8, 0.4, 0.1, 0.3, 0.7, 0.2}}};
    QVariantMap state{{"busy", true},
                      {"activity", QVariantMap{{"phase", "recording"},
                                               {"trigger", "shortcut"},
                                               {"source", "DJI Mic Mini"}}},
                      {"feedback", feedback}};
    window->setProperty("snapshot", state);
    auto *clock = window->findChild<QQuickItem *>("recordingClock");
    auto *limit = window->findChild<QQuickItem *>("recordingLimitNotice");
    auto *text = window->findChild<QQuickItem *>("dictationTranscript");
    QVERIFY(clock && limit && text);
    QCOMPARE(clock->property("text").toString(), "2:25");
    QCOMPARE(limit->property("text").toString(), "Recording stops in 0:27");
    QCOMPARE(text->property("text").toString(), "A provisional sentence");
    QTest::qWait(100);
    const QString capture = qEnvironmentVariable("SOTTO_GUI_LIVE_CAPTURE");
    if (!capture.isEmpty())
      QVERIFY(window->grabWindow().save(capture));
    auto *hud = window->findChild<QQuickWindow *>("dictationHud");
    QVERIFY(hud);
    QVERIFY(hud->flags().testFlag(Qt::WindowDoesNotAcceptFocus));
    QVERIFY(hud->flags().testFlag(Qt::WindowTransparentForInput));
    const QString hudCapture = qEnvironmentVariable("SOTTO_GUI_HUD_CAPTURE");
    if (!hudCapture.isEmpty()) {
      hud->show();
      QTest::qWait(50);
      QVERIFY(hud->grabWindow().save(hudCapture));
      hud->hide();
    }
    feedback["limitReached"] = true;
    feedback["levels"] = QVariantList{};
    state["feedback"] = feedback;
    state["activity"] = QVariantMap{{"phase", "processing"}};
    window->setProperty("snapshot", state);
    QCOMPARE(limit->property("text").toString(),
             "Stopped at the recording limit");
    state["busy"] = false;
    state["activity"] = QVariantMap{{"phase", "completed"}};
    state["result"] =
        QVariantMap{{"text", "Final sentence."}, {"delivery", "preview"}};
    window->setProperty("snapshot", state);
    QCOMPARE(text->property("text").toString(), "Final sentence.");
    QCOMPARE(warnings.count(), 0);
  }
  void shortcutKeyAndCheckAreVisibleWithoutEnablingRecording() {
    Bridge bridge(true);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    auto *key = window->findChild<QQuickItem *>("configuredShortcutKey");
    QVERIFY(key);
    QCOMPARE(key->property("text").toString(), "Menu");
    auto state = bridge.snapshot();
    auto shortcut = state["shortcut"].toMap();
    shortcut["check"] = QVariantMap{{"active", true},
                                    {"blocked", true},
                                    {"held", true},
                                    {"presses", 1},
                                    {"releases", 0},
                                    {"remainingSeconds", 20},
                                    {"message", "Press detected"}};
    state["shortcut"] = shortcut;
    window->setProperty("snapshot", state);
    auto *test = window->findChild<QQuickItem *>("microphoneTestButton");
    QVERIFY(test && !test->isEnabled());
    window->setProperty("page", 4);
    QTest::qWait(50);
    auto *result = window->findChild<QQuickItem *>("shortcutCheckResult");
    QVERIFY(result);
    QVERIFY(result->property("text").toString().contains("Presses: 1"));
    auto *settings = window->findChild<QQuickItem *>("shortcutSettings");
    QVERIFY(settings);
    const QString capture = qEnvironmentVariable("SOTTO_GUI_SHORTCUT_CAPTURE");
    if (!capture.isEmpty()) {
      for (auto *parent = settings->parentItem(); parent;
           parent = parent->parentItem()) {
        if (parent->property("contentY").isValid()) {
          parent->setProperty("contentY",
                              settings->mapToItem(parent, QPointF()).y() +
                                  parent->property("contentY").toReal());
          break;
        }
      }
      QTest::qWait(50);
      QVERIFY(window->grabWindow().save(capture));
    }
    QCOMPARE(warnings.count(), 0);
  }
  void activeMicrophoneTestCanFinishWhenServerIsBusy() {
    Bridge bridge(true);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QTRY_VERIFY(window->property("serverReady").toBool());
    auto *button = window->findChild<QQuickItem *>("microphoneTestButton");
    QVERIFY(button && button->isEnabled());
    auto snapshot = [](const QString &phase, const QString &trigger) {
      return QVariantMap{
          {"busy", true},
          {"activity", QVariantMap{{"phase", phase}, {"trigger", trigger}}}};
    };
    window->setProperty("snapshot", snapshot("recording", "test"));
    emit bridge.reply(
        "connection",
        QVariantMap{{"ready", false},
                    {"message", "Server is handling a recording."}});
    QVERIFY(!window->property("serverReady").toBool());
    QCOMPARE(window->property("connection").toString(),
             "Server is handling a recording.");
    QVERIFY(button->isEnabled());
    QCOMPARE(button->property("text").toString(), "Finish test");
    QSignalSpy failed(&bridge, &Bridge::failed);
    // Showing Cancel changes the row layout; click its settled screen geometry.
    QTest::qWait(50);
    const auto center =
        button->mapToScene(QPointF(button->width() / 2, button->height() / 2));
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QTRY_COMPARE(failed.count(), 1);
    // Preview refuses mutations, but the actual click must issue stop, not
    // start.
    QCOMPARE(failed.first().at(0).toString(), "stop");
    window->setProperty("snapshot", snapshot("processing", "test"));
    QVERIFY(!button->isEnabled());
    QCOMPARE(button->property("text").toString(), "Transcribing…");
    window->setProperty("snapshot", snapshot("recording", "shortcut"));
    QVERIFY(!button->isEnabled());
    QCOMPARE(button->property("text").toString(), "Test microphone");
    window->setProperty(
        "snapshot",
        QVariantMap{{"busy", false},
                    {"activity", QVariantMap{{"phase", "completed"}}}});
    QTRY_VERIFY(window->property("serverReady").toBool());
    QVERIFY(button->isEnabled());
    emit bridge.reply(
        "connection",
        QVariantMap{{"ready", false},
                    {"message", "Server models are unavailable."}});
    QVERIFY(!button->isEnabled());
    QCOMPARE(window->property("connection").toString(),
             "Server models are unavailable.");
  }
};
QTEST_MAIN(BridgeTest)
#include "BridgeTest.moc"
