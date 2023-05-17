//
//  IVTMovDataType.h
//
//  Created by Osl on 2020/2/7.
//  Copyright © 2020 Gavin. All rights reserved.
//

#ifndef IVTMovDataType_h
#define IVTMovDataType_h

#ifdef __cplusplus

#define PACKED() __attribute__((packed))

template <class T, std::size_t... N>
constexpr T _bswap_impl(T i, std::index_sequence<N...>) {
  return (((i >> N * CHAR_BIT & std::uint8_t(-1))
           << (sizeof(T) - 1 - N) * CHAR_BIT) |
          ...);
}
template <class T, class U = std::make_unsigned_t<T>> constexpr U bswap(T i) {
  return _bswap_impl<U>(i, std::make_index_sequence<sizeof(T)>{});
}
template <size_t size> struct sized_unsigned_type {};

template <> struct sized_unsigned_type<2> { typedef uint16_t type; };

template <> struct sized_unsigned_type<4> { typedef uint32_t type; };

template <> struct sized_unsigned_type<8> { typedef uint64_t type; };

template <size_t size> inline void copystr(char (&d)[size], const char *s) {
  using unsigned_type = typename sized_unsigned_type<size>::type;
  *((unsigned_type *)d) = *((unsigned_type *)s);
}

template <size_t... N>
inline void _copy_impl(void *dest, const void *src, std::index_sequence<N...>) {
  struct Helper {
    uint64_t s1;
    uint64_t s2;
  };
  ((*(((Helper *)dest) + N) = *(((Helper *)src) + N)), ...);
}

template <size_t size> inline size_t copy(void *dest, const void *src) {
#ifdef DEBUG
    memcpy(dest, src, size);
#else
  if constexpr (size >= 16) {
    _copy_impl(dest, src, std::make_index_sequence<size / 16>{});
    copy<size % 16>((uint8_t *)dest + (size / 16 * 16),
                    (uint8_t *)src + (size / 16 * 16));
  } else if constexpr (size > 8) {
    *((uint64_t *)dest) = *((uint64_t *)src);
    *((uint64_t *)((uint8_t *)dest + (size - 8))) =
        *((uint64_t *)((uint8_t *)src + (size - 8)));
  } else if constexpr (size == 8) {
    *((uint64_t *)dest) = *((uint64_t *)src);
  } else if constexpr (size > 4) {
    *((uint32_t *)dest) = *((uint32_t *)src);
    *((uint32_t *)((uint8_t *)dest + (size - 4))) =
        *((uint32_t *)((uint8_t *)src + (size - 4)));
  } else if constexpr (size == 4) {
    *((uint32_t *)dest) = *((uint32_t *)src);
  } else if constexpr (size == 3) {
    *((uint16_t *)dest) = *((uint16_t *)src);
    *((uint8_t *)dest + 2) = *((uint8_t *)src + 2);
  } else if constexpr (size == 2) {
    *((uint16_t *)dest) = *((uint16_t *)src);
  } else if constexpr (size == 1) {
    *((uint8_t *)dest) = *((uint8_t *)src);
  }
#endif
  return size;
}

inline auto operator""_MB(unsigned long long const x) -> long {
  return 1024L * 1024L * x;
}

inline auto operator""_KB(unsigned long long const x) -> long { return 1024L * x; }

template <class T> class PACKED() BigEndian {
  using unsigned_type = typename sized_unsigned_type<sizeof(T)>::type;
  unsigned_type v;

public:
  constexpr BigEndian() : v(0) {}
  constexpr BigEndian(T v) : v(bswap((unsigned_type)v)) {}

  template <class A,
            std::enable_if_t<std::is_convertible<A, T>::value, int> = 0>
  constexpr BigEndian(A v) : BigEndian(T(v)) {}

  operator T() const {
    T ret;
    *((unsigned_type *)&ret) = bswap(v);
    return ret;
  }

  template <class U, std::enable_if_t<std::is_integral<U>::value && std::is_integral<T>::value && sizeof(T) >= sizeof(U), int> = 0>
  operator BigEndian<U>&() const {
    return *(BigEndian<U> *)((uint8_t *)this + (sizeof(T) - sizeof(U)));
  }
};

template <size_t size, size_t offset = (size / 2)> class FixedFloat {
  friend class BigEndian<FixedFloat<size, offset>>;
  using unsigned_type = typename sized_unsigned_type<size / 8>::type;
  using signed_type = std::make_signed_t<unsigned_type>;
  static constexpr unsigned_type div = 1 << offset ;
  signed_type value;

  constexpr FixedFloat() : value(0) {}
  constexpr operator unsigned_type() const { return value; }

public:
  template <class T, std::enable_if_t<std::is_integral<T>::value ||
                                          std::is_floating_point<T>::value,
                                      int> = 0>
  constexpr FixedFloat(T v) : value(v * div) {}

  operator double() const { return value / (double)div; }

  operator float() const { return (float)(value / div); }
};

typedef BigEndian<int> bint32_t;
typedef BigEndian<uint> buint32_t;
typedef BigEndian<int16_t> bint16_t;
typedef BigEndian<uint16_t> buint16_t;
typedef BigEndian<int64_t> bint64_t;
typedef BigEndian<uint64_t> buint64_t;
typedef BigEndian<FixedFloat<16>> bff16;
typedef BigEndian<FixedFloat<32>> bff32;
typedef BigEndian<FixedFloat<32,30>> bff32uvw;
typedef bint32_t bint;
typedef buint32_t buint;
typedef struct {
    bff32 a;
    bff32 b;
    bff32uvw u;
    bff32 c;
    bff32 d;
    bff32uvw v;
    bff32 x;
    bff32 y;
    bff32uvw w;
} Matrix;

#endif
#endif /* IVTMovDataType_h */
