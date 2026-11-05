#pragma once

#include <QByteArray>
#include <QVariant>

// The small part of MessagePack that Neovim's RPC needs, to and from QVariant.
// Maps become QVariantMap and arrays QVariantList; Neovim's ext types (buffer,
// window and tabpage handles) decode as their integer id.
namespace Msgpack {

void encode(QByteArray &out, const QVariant &value);

// Decode one value from [pos, data.size()) and advance pos past it. Returns
// false, leaving pos alone, if the value isn't complete yet.
bool decode(const QByteArray &data, qsizetype &pos, QVariant &value);

} // namespace Msgpack
