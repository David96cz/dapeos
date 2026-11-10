/****************************************************************************
** Meta object code from reading C++ file 'xdgnotificationsinterface.h'
**
** Created by: The Qt Meta Object Compiler version 68 (Qt 6.8.2)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include "xdgnotificationsinterface.h"
#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'xdgnotificationsinterface.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 68
#error "This file was generated using the moc from 6.8.2. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN36OrgFreedesktopNotificationsInterfaceE_t {};
} // unnamed namespace


#ifdef QT_MOC_HAS_STRINGDATA
static constexpr auto qt_meta_stringdata_ZN36OrgFreedesktopNotificationsInterfaceE = QtMocHelpers::stringData(
    "OrgFreedesktopNotificationsInterface",
    "ActionInvoked",
    "",
    "id",
    "action_key",
    "ActivationToken",
    "activation_token",
    "NotificationClosed",
    "reason",
    "CloseNotification",
    "QDBusPendingReply<>",
    "GetCapabilities",
    "QDBusPendingReply<QStringList>",
    "GetServerInformation",
    "QDBusPendingReply<QString,QString,QString,QString>",
    "QDBusReply<QString>",
    "QString&",
    "vendor",
    "version",
    "spec_version",
    "Notify",
    "QDBusPendingReply<uint>",
    "app_name",
    "replaces_id",
    "app_icon",
    "summary",
    "body",
    "actions",
    "QVariantMap",
    "hints",
    "timeout"
);
#else  // !QT_MOC_HAS_STRINGDATA
#error "qtmochelpers.h not found or too old."
#endif // !QT_MOC_HAS_STRINGDATA

Q_CONSTINIT static const uint qt_meta_data_ZN36OrgFreedesktopNotificationsInterfaceE[] = {

 // content:
      12,       // revision
       0,       // classname
       0,    0, // classinfo
       8,   14, // methods
       0,    0, // properties
       0,    0, // enums/sets
       0,    0, // constructors
       0,       // flags
       3,       // signalCount

 // signals: name, argc, parameters, tag, flags, initial metatype offsets
       1,    2,   62,    2, 0x06,    1 /* Public */,
       5,    2,   67,    2, 0x06,    4 /* Public */,
       7,    2,   72,    2, 0x06,    7 /* Public */,

 // slots: name, argc, parameters, tag, flags, initial metatype offsets
       9,    1,   77,    2, 0x0a,   10 /* Public */,
      11,    0,   80,    2, 0x0a,   12 /* Public */,
      13,    0,   81,    2, 0x0a,   13 /* Public */,
      13,    3,   82,    2, 0x0a,   14 /* Public */,
      20,    8,   89,    2, 0x0a,   18 /* Public */,

 // signals: parameters
    QMetaType::Void, QMetaType::UInt, QMetaType::QString,    3,    4,
    QMetaType::Void, QMetaType::UInt, QMetaType::QString,    3,    6,
    QMetaType::Void, QMetaType::UInt, QMetaType::UInt,    3,    8,

 // slots: parameters
    0x80000000 | 10, QMetaType::UInt,    3,
    0x80000000 | 12,
    0x80000000 | 14,
    0x80000000 | 15, 0x80000000 | 16, 0x80000000 | 16, 0x80000000 | 16,   17,   18,   19,
    0x80000000 | 21, QMetaType::QString, QMetaType::UInt, QMetaType::QString, QMetaType::QString, QMetaType::QString, QMetaType::QStringList, 0x80000000 | 28, QMetaType::Int,   22,   23,   24,   25,   26,   27,   29,   30,

       0        // eod
};

Q_CONSTINIT const QMetaObject OrgFreedesktopNotificationsInterface::staticMetaObject = { {
    QMetaObject::SuperData::link<QDBusAbstractInterface::staticMetaObject>(),
    qt_meta_stringdata_ZN36OrgFreedesktopNotificationsInterfaceE.offsetsAndSizes,
    qt_meta_data_ZN36OrgFreedesktopNotificationsInterfaceE,
    qt_static_metacall,
    nullptr,
    qt_incomplete_metaTypeArray<qt_meta_tag_ZN36OrgFreedesktopNotificationsInterfaceE_t,
        // Q_OBJECT / Q_GADGET
        QtPrivate::TypeAndForceComplete<OrgFreedesktopNotificationsInterface, std::true_type>,
        // method 'ActionInvoked'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'ActivationToken'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        // method 'NotificationClosed'
        QtPrivate::TypeAndForceComplete<void, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        // method 'CloseNotification'
        QtPrivate::TypeAndForceComplete<QDBusPendingReply<>, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        // method 'GetCapabilities'
        QtPrivate::TypeAndForceComplete<QDBusPendingReply<QStringList>, std::false_type>,
        // method 'GetServerInformation'
        QtPrivate::TypeAndForceComplete<QDBusPendingReply<QString,QString,QString,QString>, std::false_type>,
        // method 'GetServerInformation'
        QtPrivate::TypeAndForceComplete<QDBusReply<QString>, std::false_type>,
        QtPrivate::TypeAndForceComplete<QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<QString &, std::false_type>,
        // method 'Notify'
        QtPrivate::TypeAndForceComplete<QDBusPendingReply<uint>, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<uint, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QString &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QStringList &, std::false_type>,
        QtPrivate::TypeAndForceComplete<const QVariantMap &, std::false_type>,
        QtPrivate::TypeAndForceComplete<int, std::false_type>
    >,
    nullptr
} };

void OrgFreedesktopNotificationsInterface::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<OrgFreedesktopNotificationsInterface *>(_o);
    if (_c == QMetaObject::InvokeMetaMethod) {
        switch (_id) {
        case 0: _t->ActionInvoked((*reinterpret_cast< std::add_pointer_t<uint>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2]))); break;
        case 1: _t->ActivationToken((*reinterpret_cast< std::add_pointer_t<uint>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[2]))); break;
        case 2: _t->NotificationClosed((*reinterpret_cast< std::add_pointer_t<uint>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<uint>>(_a[2]))); break;
        case 3: { QDBusPendingReply<> _r = _t->CloseNotification((*reinterpret_cast< std::add_pointer_t<uint>>(_a[1])));
            if (_a[0]) *reinterpret_cast< QDBusPendingReply<>*>(_a[0]) = std::move(_r); }  break;
        case 4: { QDBusPendingReply<QStringList> _r = _t->GetCapabilities();
            if (_a[0]) *reinterpret_cast< QDBusPendingReply<QStringList>*>(_a[0]) = std::move(_r); }  break;
        case 5: { QDBusPendingReply<QString,QString,QString,QString> _r = _t->GetServerInformation();
            if (_a[0]) *reinterpret_cast< QDBusPendingReply<QString,QString,QString,QString>*>(_a[0]) = std::move(_r); }  break;
        case 6: { QDBusReply<QString> _r = _t->GetServerInformation((*reinterpret_cast< std::add_pointer_t<QString&>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<QString&>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString&>>(_a[3])));
            if (_a[0]) *reinterpret_cast< QDBusReply<QString>*>(_a[0]) = std::move(_r); }  break;
        case 7: { QDBusPendingReply<uint> _r = _t->Notify((*reinterpret_cast< std::add_pointer_t<QString>>(_a[1])),(*reinterpret_cast< std::add_pointer_t<uint>>(_a[2])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[3])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[4])),(*reinterpret_cast< std::add_pointer_t<QString>>(_a[5])),(*reinterpret_cast< std::add_pointer_t<QStringList>>(_a[6])),(*reinterpret_cast< std::add_pointer_t<QVariantMap>>(_a[7])),(*reinterpret_cast< std::add_pointer_t<int>>(_a[8])));
            if (_a[0]) *reinterpret_cast< QDBusPendingReply<uint>*>(_a[0]) = std::move(_r); }  break;
        default: ;
        }
    }
    if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _q_method_type = void (OrgFreedesktopNotificationsInterface::*)(uint , const QString & );
            if (_q_method_type _q_method = &OrgFreedesktopNotificationsInterface::ActionInvoked; *reinterpret_cast<_q_method_type *>(_a[1]) == _q_method) {
                *result = 0;
                return;
            }
        }
        {
            using _q_method_type = void (OrgFreedesktopNotificationsInterface::*)(uint , const QString & );
            if (_q_method_type _q_method = &OrgFreedesktopNotificationsInterface::ActivationToken; *reinterpret_cast<_q_method_type *>(_a[1]) == _q_method) {
                *result = 1;
                return;
            }
        }
        {
            using _q_method_type = void (OrgFreedesktopNotificationsInterface::*)(uint , uint );
            if (_q_method_type _q_method = &OrgFreedesktopNotificationsInterface::NotificationClosed; *reinterpret_cast<_q_method_type *>(_a[1]) == _q_method) {
                *result = 2;
                return;
            }
        }
    }
}

const QMetaObject *OrgFreedesktopNotificationsInterface::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *OrgFreedesktopNotificationsInterface::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_meta_stringdata_ZN36OrgFreedesktopNotificationsInterfaceE.stringdata0))
        return static_cast<void*>(this);
    return QDBusAbstractInterface::qt_metacast(_clname);
}

int OrgFreedesktopNotificationsInterface::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QDBusAbstractInterface::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::InvokeMetaMethod) {
        if (_id < 8)
            qt_static_metacall(this, _c, _id, _a);
        _id -= 8;
    }
    if (_c == QMetaObject::RegisterMethodArgumentMetaType) {
        if (_id < 8)
            *reinterpret_cast<QMetaType *>(_a[0]) = QMetaType();
        _id -= 8;
    }
    return _id;
}

// SIGNAL 0
void OrgFreedesktopNotificationsInterface::ActionInvoked(uint _t1, const QString & _t2)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))) };
    QMetaObject::activate(this, &staticMetaObject, 0, _a);
}

// SIGNAL 1
void OrgFreedesktopNotificationsInterface::ActivationToken(uint _t1, const QString & _t2)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))) };
    QMetaObject::activate(this, &staticMetaObject, 1, _a);
}

// SIGNAL 2
void OrgFreedesktopNotificationsInterface::NotificationClosed(uint _t1, uint _t2)
{
    void *_a[] = { nullptr, const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t1))), const_cast<void*>(reinterpret_cast<const void*>(std::addressof(_t2))) };
    QMetaObject::activate(this, &staticMetaObject, 2, _a);
}
QT_WARNING_POP
