#pragma once

#include <QObject>
#include <QWindow>

class HudSurface : public QObject {
  Q_OBJECT
public:
  using QObject::QObject;
  Q_INVOKABLE void configure(QWindow *window);
};
