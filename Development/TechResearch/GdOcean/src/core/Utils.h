#pragma once

#include <cmath>
#include <cstdint>

namespace NPCSystem {

using Uid = uint64_t;
using EntityId = uint64_t;
using SiteId = uint32_t;
using TradeId = uint32_t;

struct Vec3 {
  float x, y, z;
  Vec3(float x = 0, float y = 0, float z = 0) : x(x), y(y), z(z) {}

  float length() const { return std::sqrt(x * x + y * y + z * z); }
  float distance(const Vec3 &other) const {
    return Vec3(x - other.x, y - other.y, z - other.z).length();
  }
  Vec3 operator-(const Vec3 &other) const {
    return Vec3(x - other.x, y - other.y, z - other.z);
  }
  Vec3 operator+(const Vec3 &other) const {
    return Vec3(x + other.x, y + other.y, z + other.z);
  }
  Vec3 operator*(float s) const { return Vec3(x * s, y * s, z * s); }
  Vec3 normalized() const {
    float len = length();
    return len > 0 ? Vec3(x / len, y / len, z / len) : Vec3(0, 0, 0);
  }
};

struct Vec2 {
  float x, y;
  Vec2(float x = 0, float y = 0) : x(x), y(y) {}
  Vec2 operator*(float s) const { return Vec2(x * s, y * s); }
  float length() const { return std::sqrt(x * x + y * y); }
};

} // namespace NPCSystem
