#include "../Bridge.h"
#include "../HudSurface.h"
#include <LayerShellQt/Shell>
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QJSValue>
#include <QJsonArray>
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
    engine.setInitialProperties({{"startHidden", true}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    QVERIFY(!window->isVisible());
    window->show();
    QVERIFY(window->isVisible());
    QVERIFY(QMetaObject::invokeMethod(window, "startMicrophoneTest"));
    QVERIFY(window->property("microphoneTestStarting").toBool());
    QVERIFY(!window->close());
    QVERIFY(window->isVisible());
    QTRY_VERIFY(!window->property("microphoneTestStarting").toBool());
    window->setProperty("microphoneTestStarting", true);
    auto failedSnapshot = window->property("snapshot").toMap();
    failedSnapshot["message"] = "No microphone is available.";
    window->setProperty("snapshot", failedSnapshot);
    window->setProperty("busy", false);
    window->setProperty(
        "activity", QVariantMap{{"phase", "failed"}, {"trigger", "test"}});
    QVERIFY(QMetaObject::invokeMethod(window, "syncMicrophoneTestStart"));
    QVERIFY(!window->property("microphoneTestStarting").toBool());
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
                                    {"events", QVariantList{"0.0s  Check started", "0.5s  Press detected"}},
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
    auto *events = window->findChild<QQuickItem *>("shortcutDiagnosticsEvents");
    auto *toggle = window->findChild<QQuickItem *>("shortcutDiagnosticsToggle");
    QVERIFY(events && toggle);
    QVERIFY(QMetaObject::invokeMethod(toggle, "clicked"));
    QVERIFY(events->isVisible());
    QVERIFY(events->property("text").toString().contains("Press detected"));
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
  void microphoneProfilesKeepEditsAndDisableChangesWhileBusy() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    QFile fixture(":/qt/qml/Sotto/preview.json");
    QVERIFY(fixture.open(QIODevice::ReadOnly));
    auto sample = QJsonDocument::fromJson(fixture.readAll()).object();
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
        if (!socket->canReadLine())
          return;
        const auto request =
            QJsonDocument::fromJson(socket->readLine()).object();
        const auto action = request["action"].toString();
        const auto data = sample.contains(action) ? sample[action]
                                                  : QJsonValue(QJsonObject());
        socket->write(QJsonDocument(QJsonObject{{"ok", true}, {"data", data}})
                          .toJson(QJsonDocument::Compact) +
                      '\n');
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("page", 2);
    QTest::qWait(50);
    auto *picker = window->findChild<QQuickItem *>("microphoneProfilePicker");
    auto *create = window->findChild<QQuickItem *>("newMicrophoneProfile");
    auto *save = window->findChild<QQuickItem *>("saveMicrophonesButton");
    auto *remove = window->findChild<QQuickItem *>("deleteMicrophoneProfile");
    QVERIFY(picker && create && save && remove);
    QVERIFY(create->isEnabled());
    QVERIFY(!remove->isEnabled());
    QVERIFY(!save->isEnabled());
    auto *page = window->findChild<QQuickItem *>("microphonePage");
    QVERIFY(page);
    auto *testButton = window->findChild<QQuickItem *>("microphonePageTestButton");
    QVERIFY(testButton);
    QCOMPARE(testButton->property("text").toString(), QString("Test microphone"));
    const QString microphoneCapture = qEnvironmentVariable("SOTTO_GUI_MICROPHONE_CAPTURE");
    if (!microphoneCapture.isEmpty()) {
      auto *content = page->property("contentItem").value<QQuickItem *>();
      QVERIFY(content);
      content->setProperty("contentY", qMax(0.0, content->property("contentHeight").toReal() - content->height()));
      QTest::qWait(50);
      QVERIFY(window->grabWindow().save(microphoneCapture));
      content->setProperty("contentY", 0);
    }
    auto *mode = window->findChild<QQuickItem *>("microphoneMode");
    QVERIFY(mode);
    QTRY_COMPARE(mode->property("count").toInt(), 4);
    QVERIFY(mode->setProperty("currentIndex", 3));
    QVERIFY(QMetaObject::invokeMethod(mode, "activated", Q_ARG(int, 3)));
    QTRY_VERIFY(page->property("dirty").toBool());
    auto fixedDraft = page->property("draft").value<QJSValue>().toVariant().toMap();
    QCOMPARE(fixedDraft["mode"].toString(), QString("fixed"));
    QCOMPARE(fixedDraft["fixed"].toMap()["id"].toString(), QString("airpods"));
    QVERIFY(QMetaObject::invokeMethod(page, "loadSaved"));
    QCOMPARE(mode->property("currentIndex").toInt(), 0);
    auto findItem = [&](auto &&self, QQuickItem *parent,
                        const QString &name) -> QQuickItem * {
      for (auto *child : parent->childItems()) {
        if (child->objectName() == name)
          return child;
        if (auto *found = self(self, child, name))
          return found;
      }
      return nullptr;
    };
    auto *firstHandle = findItem(findItem, window->contentItem(),
                                 "microphoneReorderHandle0");
    auto *secondHandle = findItem(findItem, window->contentItem(),
                                  "microphoneReorderHandle1");
    QVERIFY(firstHandle && secondHandle);
    const auto start = firstHandle->mapToScene(QPointF(firstHandle->width() / 2,
                                                       firstHandle->height() / 2)).toPoint();
    const auto end = secondHandle->mapToScene(QPointF(secondHandle->width() / 2,
                                                      secondHandle->height() / 2)).toPoint();
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
    for (int step = 1; step <= 6; ++step)
      QTest::mouseMove(window, start + (end - start) * step / 6, 20);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, end);
    QTRY_VERIFY(page->property("dirty").toBool());
    auto reordered = page->property("draft").value<QJSValue>().toVariant().toMap();
    if (reordered.isEmpty())
      reordered = page->property("draft").toMap();
    QCOMPARE(reordered["priority"].toList().first().toMap()["id"].toString(),
             QString("airpods"));
    QCOMPARE(reordered["profiles"].toList().first().toMap()["priority"].toList()
                 .first().toMap()["id"].toString(), QString("airpods"));
    QVERIFY(QMetaObject::invokeMethod(page, "loadSaved"));
    QVERIFY(!save->isEnabled());
    auto draft = page->property("draft").value<QJSValue>().toVariant().toMap();
    if (draft.isEmpty())
      draft = page->property("draft").toMap();
    auto profiles = draft["profiles"].toList();
    profiles.append(QVariantMap{
        {"id", "travel"}, {"name", "Travel"}, {"priority", QVariantList{}}});
    draft["profiles"] = profiles;
    page->setProperty("draft", draft);
    QVERIFY(QMetaObject::invokeMethod(page, "selectProfile",
                                      Q_ARG(QVariant, "travel")));
    QVERIFY(page->property("dirty").toBool());
    QVERIFY(save->isEnabled());
    QCOMPARE(picker->property("currentIndex").toInt(), 1);
    window->setProperty("page", 0);
    window->setProperty("page", 2);
    QCOMPARE(window->findChild<QQuickItem *>("microphonePage"), page);
    QCOMPARE(picker->property("currentIndex").toInt(), 1);
    QVERIFY(page->property("dirty").toBool());
    // A changed server snapshot cannot replace an unsaved profile choice.
    auto polledSnapshot = sample["snapshot"].toObject();
    auto polledMicrophones = polledSnapshot["microphones"].toObject();
    polledMicrophones["revision"] = "poll-update";
    polledSnapshot["microphones"] = polledMicrophones;
    sample["snapshot"] = polledSnapshot;
    QSignalSpy snapshotChanged(&bridge, &Bridge::snapshotChanged);
    bridge.request("snapshot");
    QTRY_VERIFY(snapshotChanged.count() > 0);
    QCOMPARE(bridge.snapshot()["microphones"].toMap()["revision"].toString(),
             QString("poll-update"));
    QCOMPARE(picker->property("currentIndex").toInt(), 1);
    auto changedValue = polledMicrophones["value"].toObject();
    changedValue["hostID"] = "other-host";
    polledMicrophones["value"] = changedValue;
    polledSnapshot["microphones"] = polledMicrophones;
    sample["snapshot"] = polledSnapshot;
    bridge.request("snapshot");
    QTRY_COMPARE(bridge.snapshot()["microphones"].toMap()["value"].toMap()["hostID"].toString(),
                 QString("other-host"));
    QVERIFY(page->property("dirty").toBool());
    QVERIFY(!save->isEnabled());
    QVERIFY(!create->isEnabled());
    QVERIFY(!picker->isEnabled());
    QVERIFY(QMetaObject::invokeMethod(page, "loadSaved"));
    QVERIFY(create->isEnabled());
    QVERIFY(!page->property("dirty").toBool());
    auto snapshot = bridge.snapshot();
    snapshot["busy"] = true;
    window->setProperty("snapshot", snapshot);
    QVERIFY(!save->isEnabled());
    QVERIFY(!create->isEnabled());
    QVERIFY(!picker->isEnabled());
    snapshot["busy"] = false;
    window->setProperty("snapshot", snapshot);
    QVERIFY(QMetaObject::invokeMethod(page, "loadSaved"));
    QVERIFY(!page->property("dirty").toBool());
    QCOMPARE(picker->property("currentIndex").toInt(), 0);
    QVERIFY(
        QMetaObject::invokeMethod(page, "editName", Q_ARG(QVariant, false)));
    auto *dialog = window->findChild<QObject *>("microphoneProfileDialog");
    QVERIFY(dialog);
    const auto revision = page->property("revision").toString();
    auto microphones = snapshot["microphones"].toMap();
    microphones["revision"] = "external-change";
    snapshot["microphones"] = microphones;
    sample["snapshot"] = QJsonObject::fromVariantMap(snapshot);
    bridge.request("snapshot");
    QTRY_COMPARE(
        bridge.snapshot()["microphones"].toMap()["revision"].toString(),
        QString("external-change"));
    QCOMPARE(page->property("revision").toString(), revision);
    QVERIFY(QMetaObject::invokeMethod(dialog, "close"));
    QTRY_COMPARE(page->property("revision").toString(),
                 QString("external-change"));
    QCOMPARE(warnings.count(), 0);
  }
  void historyKeepsSelectionAndScopesConfirmedActions() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    QFile fixture(":/qt/qml/Sotto/preview.json");
    QVERIFY(fixture.open(QIODevice::ReadOnly));
    auto sample = QJsonDocument::fromJson(fixture.readAll()).object();
    auto items = sample["history"].toObject()["items"].toArray();
    QJsonObject deleted, audio;
    QString requestedSource;
    int reads = 0;
    bool correlate = true;
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
        if (!socket->canReadLine()) return;
        const auto request = QJsonDocument::fromJson(socket->readLine()).object();
        const auto action = request["action"].toString();
        auto data = sample.value(action);
        if (action == "history") {
          ++reads;
          requestedSource = request["source"].toString();
          data = QJsonObject{{"items", items}, {"nextCursor", "older"}, {"queryID",correlate ? request["queryID"] : QJsonValue()}, {"server",sample["snapshot"].toObject()["server"]}};
        } else if (action == "deleteHistory") {
          deleted = request;
          items.removeAt(0);
          data = QJsonObject{{"id",request["id"]},{"server",request["server"]}};
        } else if (action == "historyAudio") {
          audio = request;
          socket->write(QJsonDocument(QJsonObject{{"ok",false},{"error","Recording no longer available. Refresh history."}}).toJson(QJsonDocument::Compact) + '\n');
          return;
        }
        socket->write(QJsonDocument(QJsonObject{{"ok",true},{"data",data}}).toJson(QJsonDocument::Compact) + '\n');
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("page",1);
    auto *page = window->findChild<QQuickItem *>("historyPage");
    QVERIFY(page);
    QTRY_COMPARE(page->property("records").toList().size(), 2);
    QCOMPARE(page->property("selectedID").toString(), "");
    page->setProperty("selectedID", "preview");
    auto *older = page->findChild<QQuickItem *>("olderHistory");
    auto *remove = page->findChild<QQuickItem *>("deleteHistory");
    auto *copy = page->findChild<QQuickItem *>("copyHistory");
    auto *date = page->findChild<QQuickItem *>("historyDetailDate");
    auto *open = page->findChild<QQuickItem *>("openHistoryAudio");
    auto *transcript = page->findChild<QQuickItem *>("historyTranscript");
    QVERIFY(older && remove && copy && date && open && transcript);
    QVERIFY(!date->property("text").toString().isEmpty());
    QVERIFY(QMetaObject::invokeMethod(copy, "clicked"));
    QCOMPARE(copy->property("text").toString(), QString("Copied"));
    QVERIFY(open->isEnabled());
    QVERIFY(QMetaObject::invokeMethod(open,"clicked"));
    QTRY_VERIFY(!audio.isEmpty());
    QCOMPARE(audio["id"].toString(),"preview");
    QCOMPARE(audio["kind"].toString(),"inference");
    QTRY_VERIFY(page->property("message").toString().contains("no longer available"));
    page->setProperty("selectedID","preview-2");
    QCOMPARE(copy->property("text").toString(), QString("Copy"));
    QVERIFY(QMetaObject::invokeMethod(older,"clicked"));
    QTRY_VERIFY(!page->property("loading").toBool());
    QCOMPARE(page->property("selectedID").toString(),"preview-2");
    auto *list = page->findChild<QQuickItem *>("historyList");
    QVERIFY(list);
    QCOMPARE(list->property("count").toInt(),2);
    auto *handle = window->findChild<QQuickItem *>("historyResizeHandle");
    QVERIFY(handle);
    const auto originalWidth = list->width();
    const auto start = handle->mapToScene(QPointF(handle->width() / 2,
                                                  handle->height() / 2)).toPoint();
    const auto end = start + QPoint(65, 0);
    QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
    for (int step = 1; step <= 5; ++step)
      QTest::mouseMove(window, start + (end - start) * step / 5, 20);
    QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, end);
    QTRY_VERIFY(list->width() > originalWidth + 30);
    page->setProperty("deviceID","desktop");
    QCOMPARE(list->property("count").toInt(),1);
    QCOMPARE(page->property("selectedID").toString(),"preview");
    page->setProperty("deviceID","");
    QVERIFY(QMetaObject::invokeMethod(remove,"clicked"));
    auto *dialog = window->findChild<QObject *>("deleteHistoryDialog");
    QVERIFY(dialog);
    QVERIFY(dialog->property("visible").toBool());
    QVERIFY(deleted.isEmpty());
    page->setProperty("selectedID","preview-2");
    auto *confirm = window->findChild<QQuickItem *>("confirmHistoryDelete");
    QVERIFY(confirm);
    QVERIFY(QMetaObject::invokeMethod(confirm,"clicked"));
    QTRY_VERIFY(!deleted.isEmpty());
    QCOMPARE(deleted["id"].toString(),"preview");
    QTRY_VERIFY(!page->property("loading").toBool());
    QCOMPARE(page->property("selectedID").toString(),"preview-2");
    QCOMPARE(list->property("count").toInt(),1);
    QVERIFY(QMetaObject::invokeMethod(page,"filterSource",Q_ARG(QVariant,"wispr-flow")));
    QTRY_COMPARE(requestedSource, "wispr-flow");
    QTRY_VERIFY(!page->property("loading").toBool());
    auto snapshot = sample["snapshot"].toObject();
    snapshot["server"] = "https://another.example.com";
    sample["snapshot"] = snapshot;
    const int previousReads = reads;
    bridge.request("snapshot");
    QTRY_VERIFY(reads > previousReads);
    QCOMPARE(page->property("server").toString(),"https://another.example.com");
    QTRY_VERIFY(!page->property("loading").toBool());
    correlate = false;
    const int beforeLegacy = reads;
    auto *refresh = page->findChild<QQuickItem *>("refreshHistory");
    QVERIFY(refresh);
    QVERIFY(QMetaObject::invokeMethod(refresh,"clicked"));
    QTRY_VERIFY(page->property("message").toString().contains("Update Sotto"));
    QVERIFY(!page->property("loading").toBool());
    QCOMPARE(reads, beforeLegacy + 2);
    QCOMPARE(warnings.count(),0);
  }
  void processingDraftsSurviveConflictsAndNavigation() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    QFile fixture(":/qt/qml/Sotto/preview.json");
    QVERIFY(fixture.open(QIODevice::ReadOnly));
    auto sample = QJsonDocument::fromJson(fixture.readAll()).object();
    QJsonObject saved;
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
        if (!socket->canReadLine()) return;
        const auto request = QJsonDocument::fromJson(socket->readLine()).object();
        const auto action = request["action"].toString();
        auto data = sample.value(action);
        if (action == "savePreferences") {
          QCOMPARE(request["server"], sample["snapshot"].toObject()["server"]);
          saved = request["value"].toObject();
          auto response = saved;
          response["revision"] = saved["revision"].toInt() + 1;
          sample["preferences"] = response;
          data = response;
        }
        socket->write(QJsonDocument(QJsonObject{{"ok", true}, {"data", data}})
                          .toJson(QJsonDocument::Compact) + '\n');
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("page", 3);
    QVERIFY(QTest::qWaitForWindowExposed(window));
    window->requestActivate();
    QTRY_VERIFY(window->isActive());
    auto *page = window->findChild<QQuickItem *>("processingSettings");
    QVERIFY(page);
    QTRY_VERIFY(page->property("editable").toBool());
    auto *cleanup = page->findChild<QQuickItem *>("cleanupInstructions");
    auto *vocabulary = page->findChild<QQuickItem *>("recognitionVocabulary");
    auto *reset = page->findChild<QQuickItem *>("resetCleanupPrompt");
    auto *save = page->findChild<QQuickItem *>("saveProcessingSettings");
    auto *dictionary = page->findChild<QQuickItem *>("dictionaryEditor");
    auto *readiness = page->findChild<QQuickItem *>("speechModelReadiness");
    QVERIFY(cleanup && vocabulary && reset && save && dictionary && readiness);
    QTRY_COMPARE(readiness->property("text").toString(), "Ready");
    QTRY_VERIFY(!page->property("defaultPrompt").toString().isEmpty());
    cleanup->forceActiveFocus();
    cleanup->setProperty("text", "Keep my wording.");
    vocabulary->forceActiveFocus();
    vocabulary->setProperty("text", "Keep my vocabulary.");
    QVERIFY(page->property("dirty").toBool());
    QVERIFY(save->isEnabled());
    // A same-revision poll leaves the editor and focus intact.
    emit bridge.reply("preferences", sample["preferences"].toObject().toVariantMap());
    QCOMPARE(cleanup->property("text").toString(), "Keep my wording.");
    QCOMPARE(vocabulary->property("text").toString(), "Keep my vocabulary.");
    QVERIFY(vocabulary->hasActiveFocus());
    window->setProperty("page", 0);
    window->setProperty("page", 3);
    QCOMPARE(window->findChild<QQuickItem *>("processingSettings"), page);
    QCOMPARE(cleanup->property("text").toString(), "Keep my wording.");
    // The shared revision advances elsewhere while these edits remain local.
    auto newer = sample["preferences"].toObject();
    newer["revision"] = 2;
    sample["preferences"] = newer;
    emit bridge.reply("preferences", newer.toVariantMap());
    QVERIFY(page->property("changedRemotely").toBool());
    QVERIFY(!save->isEnabled());
    QCOMPARE(cleanup->property("text").toString(), "Keep my wording.");
    QVERIFY(QMetaObject::invokeMethod(page, "read", Q_ARG(QVariant, true)));
    QTRY_VERIFY(!page->property("dirty").toBool());
    QTRY_VERIFY(!page->property("reading").toBool());
    QCOMPARE(vocabulary->property("text").toString(),
             newer["preferences"].toObject()["vocabulary"].toString());
    cleanup->forceActiveFocus();
    cleanup->setProperty("text", "Temporary cleanup.");
    QVERIFY(reset->isEnabled());
    QVERIFY(QMetaObject::invokeMethod(reset, "clicked"));
    QCOMPARE(cleanup->property("text"), page->property("defaultPrompt"));
    // A reset must retain the text binding for later edits and reloads.
    cleanup->forceActiveFocus();
    cleanup->setProperty("text", "Final cleanup.");
    dictionary->setProperty("selectedIndex", 0);
    auto *listName = dictionary->findChild<QQuickItem *>("dictionaryListName");
    QVERIFY(listName);
    listName->forceActiveFocus();
    listName->setProperty("text", "Edited personal");
    QVERIFY(QMetaObject::invokeMethod(listName, "textEdited"));
    QVERIFY(QMetaObject::invokeMethod(dictionary, "addList"));
    QCOMPARE(listName->property("text").toString(), "New list");
    QList<QQuickItem *> pending{window->contentItem()};
    QList<QQuickItem *> listToggles;
    while (!pending.isEmpty()) {
      auto *item = pending.takeLast();
      if (item->objectName() == "dictionaryListToggle")
        listToggles.append(item);
      for (auto *child : item->childItems())
        pending.append(child);
    }
    QCOMPARE(listToggles.size(), 2);
    dictionary->setProperty("selectedIndex", 0);
    QCOMPARE(listName->property("text").toString(), "Edited personal");
    auto *firstList = listToggles.last();
    QVERIFY(QMetaObject::invokeMethod(firstList, "clicked"));
    QCOMPARE(dictionary->property("selectedIndex").toInt(), -1);
    QVERIFY(!listName->isVisible());
    QVERIFY(QMetaObject::invokeMethod(firstList, "clicked"));
    QCOMPARE(dictionary->property("selectedIndex").toInt(), 0);
    QVERIFY(listName->isVisible());
    auto *words = dictionary->findChild<QQuickItem *>("dictionaryWords");
    QVERIFY(words);
    auto *word = words->property("currentItem").value<QQuickItem *>();
    QVERIFY(word);
    auto *aliases = word->findChild<QQuickItem *>("dictionaryAliases");
    auto *priority = word->findChild<QQuickItem *>("dictionaryPriority");
    QVERIFY(aliases && priority);
    aliases->forceActiveFocus();
    aliases->setProperty("text", "so, too\nso toe");
    priority->setProperty("checked", false);
    QVERIFY(QMetaObject::invokeMethod(priority, "clicked"));
    QVERIFY(QMetaObject::invokeMethod(save, "clicked"));
    QTRY_VERIFY(!saved.isEmpty());
    QTRY_VERIFY(!page->property("saving").toBool());
    QCOMPARE(saved["revision"].toInt(), 2);
    QCOMPARE(saved["preferences"].toObject()["proofreadingPrompt"].toString(), "Final cleanup.");
    const auto savedDictionary = saved["preferences"].toObject()["dictionary"].toObject();
    const auto savedEntries = savedDictionary["lists"].toArray()[0].toObject()["entries"].toArray();
    QCOMPARE(savedEntries[0].toObject()["aliases"].toArray(), QJsonArray({"so, too", "so toe"}));
    QCOMPARE(savedEntries[0].toObject()["isPriority"].toBool(), false);
    QCOMPARE(savedEntries[0].toObject()["id"].toString(), "sotto");
    QCOMPARE(savedEntries[1], newer["preferences"].toObject()["dictionary"].toObject()["lists"].toArray()[0].toObject()["entries"].toArray()[1]);
    QCOMPARE(saved["preferences"].toObject()["vocabulary"], newer["preferences"].toObject()["vocabulary"]);
    emit bridge.reply("preferences", newer.toVariantMap());
    QCOMPARE(cleanup->property("text").toString(), "Final cleanup.");
    QVERIFY(!page->property("changedRemotely").toBool());
    QVERIFY(!page->property("dirty").toBool());
    // A failed save keeps the draft and shows its actionable error.
    cleanup->forceActiveFocus();
    cleanup->setProperty("text", "Unsaved after failure.");
    page->setProperty("saving", true);
    emit bridge.failed("savePreferences", "Check the dictionary replacement phrases.");
    QTRY_VERIFY(!page->property("reading").toBool());
    QCOMPARE(cleanup->property("text").toString(), "Unsaved after failure.");
    QVERIFY(page->property("dirty").toBool());
    QCOMPARE(page->property("message").toString(), "Check the dictionary replacement phrases.");
    const QString capture = qEnvironmentVariable("SOTTO_GUI_PROCESSING_CAPTURE");
    if (!capture.isEmpty()) {
      dictionary->setProperty("selectedIndex", -1);
      for (auto *parent = dictionary->parentItem(); parent; parent = parent->parentItem()) {
        if (parent->property("contentY").isValid()) {
          parent->setProperty("contentY", dictionary->mapToItem(parent, QPointF()).y() + parent->property("contentY").toReal());
          break;
        }
      }
      QTest::qWait(50);
      QVERIFY(window->grabWindow().save(capture));
      dictionary->setProperty("selectedIndex", 0);
    }
    auto legacy = newer;
    auto legacyPreferences = legacy["preferences"].toObject();
    legacyPreferences.remove("dictionary");
    legacy["preferences"] = legacyPreferences;
    QVERIFY(QMetaObject::invokeMethod(page, "load", Q_ARG(QVariant, legacy.toVariantMap())));
    QCOMPARE(dictionary->property("wordCount").toInt(), 0);
    QVERIFY(QMetaObject::invokeMethod(dictionary, "addList"));
    QCOMPARE(dictionary->property("lists").value<QJSValue>().toVariant().toList().size(), 1);
    QVERIFY(page->property("dirty").toBool());
    QCOMPARE(warnings.count(), 0);
  }
  void connectionSetupMasksSecretsAndRequiresVerifiedSave() {
    QTemporaryDir directory;
    qputenv("XDG_RUNTIME_DIR", directory.path().toUtf8());
    QVERIFY(QDir().mkpath(directory.path() + "/sotto-client"));
    QLocalServer server;
    QVERIFY(server.listen(directory.path() + "/sotto-client/control.sock"));
    QStringList actions;
    connect(&server, &QLocalServer::newConnection, &server, [&] {
      auto *socket = server.nextPendingConnection();
      connect(socket, &QLocalSocket::readyRead, socket, [&, socket] {
        if (!socket->canReadLine())
          return;
        const auto request =
            QJsonDocument::fromJson(socket->readLine()).object();
        const auto action = request["action"].toString();
        actions << action;
        QJsonObject data{{"version", 1}, {"setupRequired", true}};
        if (action == "testConnection") {
          QCOMPARE(request["accessToken"].toString(), "test-secret");
          data = {{"ticket", "verified"},
                  {"hosts", QJsonArray{"desktop"}},
                  {"hostID", "desktop"},
                  {"message", "Connected. Save to use it."}};
        }
        socket->write(QJsonDocument(QJsonObject{{"ok", true}, {"data", data}})
                          .toJson(QJsonDocument::Compact) +
                      '\n');
      });
    });
    Bridge bridge(false);
    QTRY_VERIFY(bridge.connected());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
    QSignalSpy warnings(&engine, &QQmlEngine::warnings);
    engine.load(QUrl::fromLocalFile(QString(SOTTO_QML_DIR) + "/Main.qml"));
    QVERIFY(!engine.rootObjects().isEmpty());
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVERIFY(window);
    window->setProperty("page", 4);
    QTest::qWait(50);
    auto *settings = window->findChild<QQuickItem *>("connectionSettings");
    auto *address = window->findChild<QQuickItem *>("connectionServer");
    auto *token = window->findChild<QQuickItem *>("connectionToken");
    auto *check = window->findChild<QQuickItem *>("testConnectionButton");
    auto *save = window->findChild<QQuickItem *>("saveConnectionButton");
    QVERIFY(settings && address && token && check && save);
    QVERIFY(token->property("text").toString().isEmpty());
    QVERIFY(!save->isEnabled());
    address->setProperty("text", "https://speech.example.com");
    token->setProperty("text", "test-secret");
    QVERIFY(!token->property("displayText").toString().contains("test-secret"));
    QVERIFY(check->isEnabled());
    QVERIFY(QMetaObject::invokeMethod(check, "clicked"));
    QVERIFY(token->property("text").toString().isEmpty());
    QTRY_VERIFY(save->isEnabled());
    QVERIFY(!actions.contains("test"));
    window->setProperty("snapshot", QVariantMap{{"busy", true}});
    QVERIFY(!save->isEnabled());
    window->setProperty("snapshot", QVariantMap{{"busy", false}});
    QVERIFY(save->isEnabled());
    QVERIFY(QMetaObject::invokeMethod(address, "textEdited"));
    QVERIFY(!save->isEnabled());
    token->setProperty("text", "another-secret");
    window->hide();
    QVERIFY(token->property("text").toString().isEmpty());
    QCOMPARE(warnings.count(), 0);
  }
  void activeMicrophoneTestCanFinishWhenServerIsBusy() {
    Bridge bridge(true);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.rootContext()->setContextProperty(
        "portalShortcuts", QVariantMap{{"plasma", false}, {"supported", false}, {"trigger", ""}, {"message", ""}});
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
int main(int argc, char **argv) {
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
  LayerShellQt::Shell::useLayerShell();
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif
  QApplication app(argc, argv);
  BridgeTest test;
  return QTest::qExec(&test, argc, argv);
}
#include "BridgeTest.moc"
