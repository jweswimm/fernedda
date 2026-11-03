#include "Simulator.h"
#include "SignalKStore.h"

#include <QDateTime>
#include <QRandomGenerator>
#include <QVariantMap>
#include <algorithm>
#include <cmath>

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kHullSpeed = 3.9;      // m/s, ~7.6 kn
constexpr double kVariation = 0.27;     // rad east
constexpr double kBatteryAh = 400;
const char *kSource = "simulator";

double wrap(double a) // to (-pi, pi]
{
    while (a > kPi) a -= 2 * kPi;
    while (a <= -kPi) a += 2 * kPi;
    return a;
}
double wrap2pi(double a)
{
    a = std::fmod(a, 2 * kPi);
    return a < 0 ? a + 2 * kPi : a;
}
double approach(double v, double target, double rate, double dt)
{
    return v + (target - v) * (1 - std::exp(-dt * rate));
}
double gauss()
{
    // Box–Muller
    auto *r = QRandomGenerator::global();
    double u = std::max(1e-12, r->generateDouble()), v = r->generateDouble();
    return std::sqrt(-2 * std::log(u)) * std::cos(2 * kPi * v);
}

// Rough polar: fraction of true wind speed achieved at a given true wind angle.
double polar(double twaAbs)
{
    const double deg = twaAbs * 180 / kPi;
    if (deg < 28) return 0;
    if (deg < 45) return 0.45 * (deg - 28) / 17;
    if (deg < 60) return 0.45 + 0.12 * (deg - 45) / 15;
    if (deg < 110) return 0.57 + 0.05 * (deg - 60) / 50;
    if (deg < 150) return 0.62 - 0.1 * (deg - 110) / 40;
    return 0.52 - 0.07 * (deg - 150) / 30;
}
} // namespace

Simulator::Simulator(QObject *parent) : QObject(parent)
{
    m_timer.setInterval(500);
    connect(&m_timer, &QTimer::timeout, this, [this] {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        const double dt = (now - m_last) / 1000.0;
        m_last = now;
        step(dt, now);
        publish(now);
    });
}

void Simulator::start()
{
    if (m_timer.isActive())
        return;
    // Fast-forward through the last 3 hours so plots open with history.
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const int seedSeconds = 3 * 3600;
    for (int i = seedSeconds; i > 0; --i) {
        const qint64 ts = now - qint64(i) * 1000;
        step(1.0, ts);
        publish(ts);
    }
    m_last = now;
    m_timer.start();
}

void Simulator::stop()
{
    m_timer.stop();
}

double Simulator::noise(double &state, double dt, double tau, double sigma)
{
    // Ornstein–Uhlenbeck: mean-reverting random walk with time constant tau.
    state += -state * dt / tau + sigma * std::sqrt(2 * dt / tau) * gauss();
    return state;
}

void Simulator::step(double dt, qint64)
{
    dt = std::clamp(dt, 0.0, 5.0);
    t += dt;

    // Wind: slow veer/back plus gusts.
    twd = wrap2pi(3.84 + 0.25 * std::sin(t / 900) + noise(nTwd, dt, 120, 0.08));
    tws = std::max(0.5, 6.0 + 1.6 * std::sin(t / 420) + noise(nGust, dt, 8, 0.9)
                            + noise(nTws, dt, 300, 0.8));

    // Sail for 6 min, motor for 3 min, repeat.
    phaseTimer += dt;
    if (phaseTimer > (motoring ? 180 : 360)) {
        phaseTimer = 0;
        motoring = !motoring;
    }

    // Steering: close-hauled tacks while sailing, straight into it while motoring.
    tackTimer += dt;
    if (!motoring && tackTimer > 240) {
        tackTimer = 0;
        tack = -tack;
    }
    const double targetTwa = motoring ? 0.35 * tack : 0.82 * tack; // rad
    const double targetHeading = wrap2pi(twd - targetTwa);
    heading = wrap2pi(heading + std::clamp(wrap(targetHeading - heading), -0.08 * dt, 0.08 * dt));
    twa = wrap(twd - heading);

    // Engine
    const double targetRpm = motoring ? 2250 + 40 * std::sin(t / 13) : 0;
    rpm = approach(rpm, targetRpm, motoring ? 0.6 : 1.5, dt);
    if (rpm < 5) rpm = 0;
    const bool running = rpm > 300;
    coolant = approach(coolant, running ? 355.5 : airT + 8, running ? 0.012 : 0.003, dt);
    oilPressure = running ? 280000 + rpm * 45 : approach(oilPressure, 0, 2, dt);
    if (running) {
        runTime += dt;
        fuel = std::max(0.0, fuel - dt * 2.0 / 3600 / 150); // ~2 L/h of a 150 L tank
    }

    // Speed
    const double sailSpeed = std::min(kHullSpeed, tws * polar(std::abs(twa)));
    const double motorSpeed = rpm / 2400.0 * 3.3;
    stw = approach(stw, motoring ? std::max(motorSpeed, sailSpeed * 0.3) : sailSpeed, 0.15, dt);

    // Current 0.35 m/s setting east-southeast.
    const double setDir = 1.9, drift = 0.35;
    const double vn = stw * std::cos(heading) + drift * std::cos(setDir);
    const double ve = stw * std::sin(heading) + drift * std::sin(setDir);
    sog = std::hypot(vn, ve);
    cog = wrap2pi(std::atan2(ve, vn));
    lat += vn * dt / 111320.0;
    lon += ve * dt / (111320.0 * std::cos(lat * kPi / 180));

    // Apparent wind (x forward, y starboard)
    const double ax = tws * std::cos(twa) + stw;
    const double ay = tws * std::sin(twa);
    aws = std::hypot(ax, ay);
    awa = std::atan2(ay, ax);

    // Heel and pitch
    const double heelTarget = motoring ? 0.02 * (awa > 0 ? -1 : 1)
                                       : -std::clamp(aws * aws * std::sin(std::abs(awa)) * 0.0045, 0.0, 0.42)
                                             * (awa > 0 ? 1 : -1);
    roll = approach(roll, heelTarget, 0.5, dt);
    pitch = 0.03 * std::sin(t * 1.3) + noise(nPitch, dt, 2, 0.015);

    // Depth: rolling seabed
    depth = std::max(2.5, 18 + 9 * std::sin(t / 520) + 4 * std::sin(t / 113) + noise(nDepth, dt, 20, 1.0));

    // Electrical
    const double daylight = std::max(0.0, std::sin(t / 2400 + 1.2));
    solarW = std::max(0.0, 260 * daylight * (0.8 + 0.2 * std::sin(t / 37)));
    const double loads = 7.5 + 2.5 * std::sin(t / 190) + noise(nLoad, dt, 30, 1.0)
                       + (motoring ? 0 : 1.5); // instruments + autopilot
    const double alternator = running ? 38.0 * std::min(1.0, (1.0 - soc) * 6 + 0.2) : 0;
    houseI = solarW / 13.6 + alternator - loads;
    soc = std::clamp(soc + houseI * dt / 3600 / kBatteryAh, 0.05, 1.0);
    const double rest = 11.9 + 1.0 * soc;
    houseV = approach(houseV, rest + (houseI > 0 ? std::min(1.6, houseI * 0.035) : houseI * 0.012), 0.3, dt);
    starterV = approach(starterV, running ? 14.1 : 12.72, 0.2, dt);

    // Tanks
    water = std::max(0.0, water - dt * 0.000002);
    black = std::min(1.0, black + dt * 0.0000012);

    // Weather
    airT = 290.5 + 1.8 * std::sin(t / 2000);
    waterT = 286.8 + 0.2 * std::sin(t / 3000);
    pressure = 101420 - t * 0.05 + 60 * std::sin(t / 1300);
    humidity = std::clamp(0.71 + 0.06 * std::sin(t / 1700), 0.0, 1.0);
}

void Simulator::publish(qint64 ts)
{
    auto *s = SignalKStore::instance();
    auto put = [&](const char *path, const QVariant &v) { s->update(QString::fromLatin1(path), v, ts, kSource); };

    put("name", QStringLiteral("Simulated boat"));
    put("navigation.position", QVariantMap{{"latitude", lat}, {"longitude", lon}});
    put("navigation.headingTrue", heading);
    put("navigation.headingMagnetic", wrap2pi(heading - kVariation));
    put("navigation.magneticVariation", kVariation);
    put("navigation.courseOverGroundTrue", cog);
    put("navigation.speedOverGround", sog);
    put("navigation.speedThroughWater", stw);
    put("navigation.attitude", QVariantMap{{"roll", roll}, {"pitch", pitch}, {"yaw", heading}});
    put("navigation.rateOfTurn", 0.0);

    put("environment.wind.angleApparent", awa);
    put("environment.wind.speedApparent", aws);
    put("environment.wind.angleTrueWater", twa);
    put("environment.wind.speedTrue", tws);
    put("environment.wind.directionTrue", twd);
    put("environment.depth.belowTransducer", depth);
    put("environment.water.temperature", waterT);
    put("environment.outside.temperature", airT);
    put("environment.outside.pressure", pressure);
    put("environment.outside.relativeHumidity", humidity);

    put("propulsion.main.revolutions", rpm / 60.0);
    put("propulsion.main.temperature", coolant);
    put("propulsion.main.oilPressure", oilPressure);
    put("propulsion.main.runTime", runTime);
    put("propulsion.main.state", rpm > 300 ? QStringLiteral("started") : QStringLiteral("stopped"));

    put("electrical.batteries.house.voltage", houseV);
    put("electrical.batteries.house.current", houseI);
    put("electrical.batteries.house.stateOfCharge", soc);
    put("electrical.batteries.house.capacity.nominal", kBatteryAh * 3600 * 12.0); // J
    put("electrical.batteries.starter.voltage", starterV);
    put("electrical.solar.main.panelPower", solarW);

    put("tanks.fuel.0.currentLevel", fuel);
    put("tanks.fuel.0.capacity", 0.150);
    put("tanks.freshWater.0.currentLevel", water);
    put("tanks.freshWater.0.capacity", 0.300);
    put("tanks.blackWater.0.currentLevel", black);
    put("tanks.blackWater.0.capacity", 0.080);
}
