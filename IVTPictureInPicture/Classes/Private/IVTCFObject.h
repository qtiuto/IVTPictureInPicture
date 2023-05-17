//
//  IVTCFObject.h
//
//  Created by Osl on 2020/2/7.
//  Copyright © 2020 Gavin. All rights reserved.
//

#ifndef IVTCFObject_h
#define IVTCFObject_h

#include <Foundation/Foundation.h>

#ifdef __cplusplus

template <class T, class OC = id, void (*release)(CFTypeRef) = CFRelease>
struct CFObject {
    static_assert(std::is_pointer<T>::value, "must be pointer type");
    T object;
    CFObject():object(nullptr){};
    CFObject(const CFObject &o): object(o.object ? (T)CFRetain(o.object) : nullptr){};
    CFObject &operator=(const CFObject &o) {
        this->~CFObject();
        object = o.object ? (T)CFRetain(o.object) : nullptr;
    };
    CFObject(CFObject &&o) : object(o.object) { o.object = nullptr; }
    CFObject(OC v) : object(CFBridgingRetain(v)) {}
    CFObject(T v) : object(v ? (T) CFRetain(v): nullptr) {}
    T get() { return object; }
    CFObject &operator=(OC v) {
        this->~CFObject();
        object = (T)CFBridgingRetain(v);
        return *this;
    }
    CFObject &operator=(T o) {
        if (o != object) {
            this->~CFObject();
            object = (T)(o ? CFRetain(o) : nullptr);
        }
        return *this;
    }
    CFObject &operator=(CFObject &&o) {
        if (&o != this) {
            std::swap(this->object, o.object);
        }
        return *this;
    }
    
    T *out() { return &object; }
    
    CFObject &operator=(std::nullptr_t v) {
        T o = object;
        object = v;
        if (o) {
            release(o);
        }
        return *this;
    }
    
    template <class... Args, class Ret = void> Ret call(Args &&... args) const {
        return ((__bridge OC)object)(std::forward<Args>(args)...);
    }
    
    operator T() const { return object; }
    
    operator OC() const { return (__bridge OC)object; }
    
    operator bool() const { return object != nullptr; }
    
    ~CFObject() {
        T o = object;
        if (o) {
            release(o);
        }
    }
};

#endif
#endif /* TSVCFObject_h */
