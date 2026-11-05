#include "Msgpack.h"

#include <QtEndian>

namespace {

template <typename T>
void put(QByteArray &out, quint8 tag, T value)
{
    out.append(char(tag));
    const T big = qToBigEndian(value);
    out.append(reinterpret_cast<const char *>(&big), sizeof(T));
}

void putInt(QByteArray &out, qint64 v)
{
    if (v >= 0 && v < 128)
        out.append(char(v));
    else
        put<qint64>(out, 0xd3, v);
}

void putSize(QByteArray &out, qsizetype n, quint8 fix, int fixMax, quint8 tag16, quint8 tag32)
{
    if (n <= fixMax)
        out.append(char(fix | n));
    else if (n <= 0xffff)
        put<quint16>(out, tag16, quint16(n));
    else
        put<quint32>(out, tag32, quint32(n));
}

class Reader {
public:
    Reader(const QByteArray &data, qsizetype pos) : m_data(data), m_pos(pos) {}
    qsizetype pos() const { return m_pos; }

    bool read(QVariant &out)
    {
        if (m_pos >= m_data.size())
            return false;
        const quint8 tag = quint8(m_data[m_pos++]);

        if (tag < 0x80) { out = qint64(tag); return true; }
        if (tag >= 0xe0) { out = qint64(qint8(tag)); return true; }
        if (tag >= 0xa0 && tag <= 0xbf) return readString(tag & 0x1f, out);
        if (tag >= 0x90 && tag <= 0x9f) return readArray(tag & 0x0f, out);
        if (tag >= 0x80 && tag <= 0x8f) return readMap(tag & 0x0f, out);

        quint64 n = 0;
        switch (tag) {
        case 0xc0: out = QVariant(); return true;
        case 0xc2: out = false; return true;
        case 0xc3: out = true; return true;
        case 0xca: { quint32 v; if (!number(v)) return false; float f; memcpy(&f, &v, 4); out = double(f); return true; }
        case 0xcb: { quint64 v; if (!number(v)) return false; double d; memcpy(&d, &v, 8); out = d; return true; }
        case 0xcc: { quint8 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xcd: { quint16 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xce: { quint32 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xcf: { quint64 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xd0: { qint8 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xd1: { qint16 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xd2: { qint32 v; if (!number(v)) return false; out = qint64(v); return true; }
        case 0xd3: { qint64 v; if (!number(v)) return false; out = v; return true; }
        case 0xc4: case 0xd9: { quint8 v; if (!number(v)) return false; n = v; return readString(n, out); }
        case 0xc5: case 0xda: { quint16 v; if (!number(v)) return false; n = v; return readString(n, out); }
        case 0xc6: case 0xdb: { quint32 v; if (!number(v)) return false; n = v; return readString(n, out); }
        case 0xdc: { quint16 v; if (!number(v)) return false; return readArray(v, out); }
        case 0xdd: { quint32 v; if (!number(v)) return false; return readArray(v, out); }
        case 0xde: { quint16 v; if (!number(v)) return false; return readMap(v, out); }
        case 0xdf: { quint32 v; if (!number(v)) return false; return readMap(v, out); }
        case 0xd4: return readExt(1, out);
        case 0xd5: return readExt(2, out);
        case 0xd6: return readExt(4, out);
        case 0xd7: return readExt(8, out);
        case 0xd8: return readExt(16, out);
        case 0xc7: { quint8 v; if (!number(v)) return false; return readExt(v, out); }
        case 0xc8: { quint16 v; if (!number(v)) return false; return readExt(v, out); }
        case 0xc9: { quint32 v; if (!number(v)) return false; return readExt(v, out); }
        }
        return false;
    }

private:
    bool available(quint64 n) const { return quint64(m_data.size() - m_pos) >= n; }

    template <typename T>
    bool number(T &v)
    {
        if (!available(sizeof(T)))
            return false;
        v = qFromBigEndian<T>(m_data.constData() + m_pos);
        m_pos += sizeof(T);
        return true;
    }

    bool readString(quint64 n, QVariant &out)
    {
        if (!available(n))
            return false;
        out = QString::fromUtf8(m_data.constData() + m_pos, qsizetype(n));
        m_pos += qsizetype(n);
        return true;
    }

    bool readArray(quint64 n, QVariant &out)
    {
        if (!available(n))      // every element takes at least a byte
            return false;
        QVariantList list;
        list.reserve(qsizetype(n));
        for (quint64 i = 0; i < n; ++i) {
            QVariant v;
            if (!read(v))
                return false;
            list.append(std::move(v));
        }
        out = std::move(list);
        return true;
    }

    bool readMap(quint64 n, QVariant &out)
    {
        QVariantMap map;
        for (quint64 i = 0; i < n; ++i) {
            QVariant k, v;
            if (!read(k) || !read(v))
                return false;
            map.insert(k.toString(), std::move(v));
        }
        out = std::move(map);
        return true;
    }

    // Neovim's handles: one type byte, then the id as a msgpack integer.
    bool readExt(quint64 n, QVariant &out)
    {
        if (!available(n + 1))
            return false;
        Reader inner(m_data, m_pos + 1);
        inner.read(out);
        m_pos += qsizetype(n + 1);
        return true;
    }

    const QByteArray &m_data;
    qsizetype m_pos;
};

} // namespace

namespace Msgpack {

void encode(QByteArray &out, const QVariant &value)
{
    switch (value.typeId()) {
    case QMetaType::Bool:
        out.append(char(value.toBool() ? 0xc3 : 0xc2));
        break;
    case QMetaType::Int:
    case QMetaType::LongLong:
        putInt(out, value.toLongLong());
        break;
    case QMetaType::QString: {
        const QByteArray utf8 = value.toString().toUtf8();
        putSize(out, utf8.size(), 0xa0, 31, 0xda, 0xdb);
        out.append(utf8);
        break;
    }
    case QMetaType::QVariantList: {
        const QVariantList list = value.toList();
        putSize(out, list.size(), 0x90, 15, 0xdc, 0xdd);
        for (const QVariant &v : list)
            encode(out, v);
        break;
    }
    case QMetaType::QVariantMap: {
        const QVariantMap map = value.toMap();
        putSize(out, map.size(), 0x80, 15, 0xde, 0xdf);
        for (auto it = map.cbegin(); it != map.cend(); ++it) {
            encode(out, it.key());
            encode(out, it.value());
        }
        break;
    }
    default:
        out.append(char(0xc0));
    }
}

bool decode(const QByteArray &data, qsizetype &pos, QVariant &value)
{
    Reader reader(data, pos);
    if (!reader.read(value))
        return false;
    pos = reader.pos();
    return true;
}

} // namespace Msgpack
