#pragma once

#include <QObject>
#include <QTimer>

// A plausible sailboat for when no Signal K server is around: tacks upwind,
// motors now and then, charges/discharges batteries, drains tanks. Writes
// SI-unit values to SignalKStore under standard Signal K paths, exactly like
// a live server would.
class Simulator : public QObject {
    Q_OBJECT
public:
    explicit Simulator(QObject *parent = nullptr);
    void start();
    void stop();

private:
    void step(double dt, qint64 timestampMs);
    void publish(qint64 timestampMs);
    double noise(double &state, double dt, double tau, double sigma);

    QTimer m_timer;
    qint64 m_last = 0;
    double t = 0;

    // Vessel state (SI units, radians)
    double lat = 47.6400, lon = -122.4300;
    double heading = 3.5, stw = 0, sog = 0, cog = 0, roll = 0, pitch = 0;
    double twd = 3.84, tws = 6.0, awa = 0, aws = 0, twa = 0;
    double depth = 15;
    int tack = 1;
    double tackTimer = 0;
    bool motoring = false;
    double phaseTimer = 0;
    double rpm = 0, coolant = 300, oilPressure = 0, runTime = 1843.2 * 3600;
    double soc = 0.86, houseV = 12.8, houseI = 0, starterV = 12.7, solarW = 0;
    double fuel = 0.64, water = 0.52, black = 0.21;
    double airT = 290.5, waterT = 286.8, pressure = 101420, humidity = 0.71;

    // Smoothed noise states
    double nTwd = 0, nTws = 0, nDepth = 0, nGust = 0, nPitch = 0, nLoad = 0;
};
