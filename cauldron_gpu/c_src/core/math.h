#pragma once

#include <cmath>

namespace cg {

struct Vec3 {
  float x = 0, y = 0, z = 0;
};

struct Quat {
  float x = 0, y = 0, z = 0, w = 1;
};

struct Mat4 {
  float m[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

  float &at(int row, int column) { return m[column * 4 + row]; }
  float at(int row, int column) const { return m[column * 4 + row]; }
};

struct Transform {
  Vec3 position;
  Quat rotation;
  Vec3 scale{1, 1, 1};
};

inline Vec3 operator+(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vec3 operator-(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline Vec3 operator*(Vec3 a, float s) { return {a.x * s, a.y * s, a.z * s}; }
inline float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline Vec3 cross(Vec3 a, Vec3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline float length(Vec3 a) { return std::sqrt(dot(a, a)); }

inline Vec3 normalize(Vec3 a) {
  float size = length(a);
  return size > 0 ? a * (1.0f / size) : Vec3{0, -1, 0};
}

inline Vec3 lerp(Vec3 a, Vec3 b, float t) { return a + (b - a) * t; }

inline Quat normalize(Quat q) {
  float size = std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
  if (size == 0) return {};
  return {q.x / size, q.y / size, q.z / size, q.w / size};
}

inline Quat nlerp(Quat a, Quat b, float t) {
  float sign = (a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w) < 0 ? -1.0f : 1.0f;
  return normalize(Quat{a.x + (b.x * sign - a.x) * t, a.y + (b.y * sign - a.y) * t,
                        a.z + (b.z * sign - a.z) * t, a.w + (b.w * sign - a.w) * t});
}

inline Vec3 rotate(Quat q, Vec3 v) {
  Vec3 axis{q.x, q.y, q.z};
  Vec3 t = cross(axis, v) * 2.0f;
  return v + t * q.w + cross(axis, t);
}

inline Transform interpolate(const Transform &a, const Transform &b, float t) {
  return {lerp(a.position, b.position, t), nlerp(a.rotation, b.rotation, t), lerp(a.scale, b.scale, t)};
}

inline Mat4 multiply(const Mat4 &a, const Mat4 &b) {
  Mat4 result;
  for (int row = 0; row < 4; row++)
    for (int column = 0; column < 4; column++) {
      float sum = 0;
      for (int k = 0; k < 4; k++) sum += a.at(row, k) * b.at(k, column);
      result.at(row, column) = sum;
    }
  return result;
}

inline Mat4 model_matrix(const Transform &transform) {
  Mat4 result;
  Vec3 x = rotate(transform.rotation, {transform.scale.x, 0, 0});
  Vec3 y = rotate(transform.rotation, {0, transform.scale.y, 0});
  Vec3 z = rotate(transform.rotation, {0, 0, transform.scale.z});
  Vec3 columns[3] = {x, y, z};
  for (int column = 0; column < 3; column++) {
    result.at(0, column) = columns[column].x;
    result.at(1, column) = columns[column].y;
    result.at(2, column) = columns[column].z;
  }
  result.at(0, 3) = transform.position.x;
  result.at(1, 3) = transform.position.y;
  result.at(2, 3) = transform.position.z;
  return result;
}

inline Mat4 normal_matrix(const Transform &transform) {
  Transform inverse_scale = transform;
  inverse_scale.position = {};
  inverse_scale.scale = {transform.scale.x != 0 ? 1 / transform.scale.x : 0,
                         transform.scale.y != 0 ? 1 / transform.scale.y : 0,
                         transform.scale.z != 0 ? 1 / transform.scale.z : 0};
  return model_matrix(inverse_scale);
}

inline Mat4 view_matrix(Vec3 eye, Quat rotation) {
  Quat inverse{-rotation.x, -rotation.y, -rotation.z, rotation.w};
  Mat4 result;
  Vec3 axes[3] = {rotate(inverse, {1, 0, 0}), rotate(inverse, {0, 1, 0}), rotate(inverse, {0, 0, 1})};
  for (int column = 0; column < 3; column++) {
    result.at(0, column) = axes[column].x;
    result.at(1, column) = axes[column].y;
    result.at(2, column) = axes[column].z;
  }
  Vec3 moved = rotate(inverse, eye) * -1.0f;
  result.at(0, 3) = moved.x;
  result.at(1, 3) = moved.y;
  result.at(2, 3) = moved.z;
  return result;
}

inline Mat4 look_along(Vec3 eye, Vec3 forward, Vec3 up) {
  Vec3 f = normalize(forward);
  Vec3 s = normalize(cross(f, up));
  Vec3 u = cross(s, f);
  Mat4 result;
  result.at(0, 0) = s.x;
  result.at(0, 1) = s.y;
  result.at(0, 2) = s.z;
  result.at(1, 0) = u.x;
  result.at(1, 1) = u.y;
  result.at(1, 2) = u.z;
  result.at(2, 0) = -f.x;
  result.at(2, 1) = -f.y;
  result.at(2, 2) = -f.z;
  result.at(0, 3) = -dot(s, eye);
  result.at(1, 3) = -dot(u, eye);
  result.at(2, 3) = dot(f, eye);
  return result;
}

inline Mat4 reversed_perspective(float fov_y, float aspect, float near_plane, float far_plane) {
  float focal = 1.0f / std::tan(fov_y * 0.5f);
  Mat4 result;
  result.at(0, 0) = focal / aspect;
  result.at(1, 1) = focal;
  result.at(2, 2) = near_plane / (far_plane - near_plane);
  result.at(2, 3) = far_plane * near_plane / (far_plane - near_plane);
  result.at(3, 2) = -1;
  result.at(3, 3) = 0;
  return result;
}

inline Mat4 reversed_orthographic(float half_width, float half_height, float near_plane, float far_plane) {
  Mat4 result;
  result.at(0, 0) = 1.0f / half_width;
  result.at(1, 1) = 1.0f / half_height;
  result.at(2, 2) = 1.0f / (far_plane - near_plane);
  result.at(2, 3) = far_plane / (far_plane - near_plane);
  return result;
}

inline Vec3 transform_point(const Mat4 &matrix, Vec3 point) {
  return {matrix.at(0, 0) * point.x + matrix.at(0, 1) * point.y + matrix.at(0, 2) * point.z + matrix.at(0, 3),
          matrix.at(1, 0) * point.x + matrix.at(1, 1) * point.y + matrix.at(1, 2) * point.z + matrix.at(1, 3),
          matrix.at(2, 0) * point.x + matrix.at(2, 1) * point.y + matrix.at(2, 2) * point.z + matrix.at(2, 3)};
}

inline Mat4 inverse(const Mat4 &matrix) {
  const float *m = matrix.m;
  Mat4 result;
  float *inv = result.m;
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
  float determinant = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  float scale = determinant != 0 ? 1.0f / determinant : 0.0f;
  for (float &value : result.m) value *= scale;
  return result;
}

}
