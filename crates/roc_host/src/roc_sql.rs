use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted};
use std::cell::RefCell;
use std::rc::Rc;

#[repr(C, align(8))]
pub struct SQLiteError {
    pub code: i64,
    pub message: roc_std::RocStr,
}

struct SQLiteConnection {
    path: String,
    connection: Rc<sqlite::Connection>,
}

thread_local! {
    static SQLITE_CONNECTIONS : RefCell<Vec<SQLiteConnection>> = const {RefCell::new(vec![])};
}

pub fn get_connection(path: &str) -> Result<Rc<sqlite::Connection>, sqlite::Error> {
    SQLITE_CONNECTIONS.with(|connections| {
        for c in connections.borrow().iter() {
            if c.path == path {
                return Ok(Rc::clone(&c.connection));
            }
        }

        let connection = match sqlite::Connection::open_with_flags(
            path,
            sqlite::OpenFlags::new()
                .with_create()
                .with_read_write()
                .with_no_mutex(),
        ) {
            Ok(new_con) => new_con,
            Err(err) => {
                return Err(err);
            }
        };

        let rc_connection = Rc::new(connection);
        let new_connection = SQLiteConnection {
            path: path.to_owned(),
            connection: Rc::clone(&rc_connection),
        };

        connections.borrow_mut().push(new_connection);
        Ok(rc_connection)
    })
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantSQLiteValue {
    Bytes = 0,
    Integer = 1,
    Null = 2,
    Real = 3,
    String = 4,
}

impl core::fmt::Debug for DiscriminantSQLiteValue {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Bytes => f.write_str("DiscriminantSQLiteValue::Bytes"),
            Self::Integer => f.write_str("DiscriminantSQLiteValue::Integer"),
            Self::Null => f.write_str("DiscriminantSQLiteValue::Null"),
            Self::Real => f.write_str("DiscriminantSQLiteValue::Real"),
            Self::String => f.write_str("DiscriminantSQLiteValue::String"),
        }
    }
}

roc_refcounted_noop_impl!(DiscriminantSQLiteValue);

#[repr(C, align(8))]
pub union UnionSQLiteValue {
    bytes: core::mem::ManuallyDrop<RocList<u8>>,
    integer: i64,
    null: (),
    real: f64,
    string: core::mem::ManuallyDrop<roc_std::RocStr>,
}

// TODO(@roc-lang): See https://github.com/roc-lang/roc/issues/6012
// const _SIZE_CHECK_union_SQLiteValue: () = assert!(core::mem::size_of::<union_SQLiteValue>() == 24);
const _ALIGN_CHECK_UNION_D_SQL_VALUE: () = assert!(core::mem::align_of::<UnionSQLiteValue>() == 8);
const _SIZE_CHECK_SQL_VALUE: () = assert!(core::mem::size_of::<SQLiteValue>() == 32);
const _ALIGN_CHECK_SQL_VALUE: () = assert!(core::mem::align_of::<SQLiteValue>() == 8);

impl SQLiteValue {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantSQLiteValue {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, DiscriminantSQLiteValue>(*bytes.as_ptr().add(24))
        }
    }

    // fn set_discriminant(&mut self, discriminant: DiscriminantSQLiteValue) {
    //     let discriminant_ptr: *mut DiscriminantSQLiteValue = (self as *mut SQLiteValue).cast();

    //     unsafe {
    //         *(discriminant_ptr.add(24)) = discriminant;
    //     }
    // }
}

#[repr(C)]
pub struct SQLiteValue {
    payload: UnionSQLiteValue,
    discriminant: DiscriminantSQLiteValue,
}

impl Clone for SQLiteValue {
    fn clone(&self) -> Self {
        use DiscriminantSQLiteValue::*;

        let payload = unsafe {
            match self.discriminant {
                Bytes => UnionSQLiteValue {
                    bytes: self.payload.bytes.clone(),
                },
                Integer => UnionSQLiteValue {
                    integer: self.payload.integer,
                },
                Null => UnionSQLiteValue { null: () },
                Real => UnionSQLiteValue {
                    real: self.payload.real,
                },
                String => UnionSQLiteValue {
                    string: self.payload.string.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for SQLiteValue {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use DiscriminantSQLiteValue::*;

        unsafe {
            match self.discriminant {
                Bytes => {
                    let field: &RocList<u8> = &self.payload.bytes;
                    f.debug_tuple("SQLiteValue::Bytes").field(field).finish()
                }
                Integer => {
                    let field: &i64 = &self.payload.integer;
                    f.debug_tuple("SQLiteValue::Integer").field(field).finish()
                }
                Null => {
                    let field: &() = &self.payload.null;
                    f.debug_tuple("SQLiteValue::Null").field(field).finish()
                }
                Real => {
                    let field: &f64 = &self.payload.real;
                    f.debug_tuple("SQLiteValue::Real").field(field).finish()
                }
                String => {
                    let field: &roc_std::RocStr = &self.payload.string;
                    f.debug_tuple("SQLiteValue::String").field(field).finish()
                }
            }
        }
    }
}

impl PartialEq for SQLiteValue {
    fn eq(&self, other: &Self) -> bool {
        use DiscriminantSQLiteValue::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                Bytes => self.payload.bytes == other.payload.bytes,
                Integer => self.payload.integer == other.payload.integer,
                Null => other.discriminant() == DiscriminantSQLiteValue::Null,
                Real => self.payload.real == other.payload.real,
                String => self.payload.string == other.payload.string,
            }
        }
    }
}

impl PartialOrd for SQLiteValue {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use DiscriminantSQLiteValue::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    Bytes => self.payload.bytes.partial_cmp(&other.payload.bytes),
                    Integer => self.payload.integer.partial_cmp(&other.payload.integer),
                    Null => Some(std::cmp::Ordering::Equal),
                    Real => self.payload.real.partial_cmp(&other.payload.real),
                    String => self.payload.string.partial_cmp(&other.payload.string),
                }
            },
        }
    }
}

impl SQLiteValue {
    pub fn unwrap_bytes(mut self) -> RocList<u8> {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Bytes);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.bytes) }
    }

    pub fn borrow_bytes(&self) -> &RocList<u8> {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Bytes);
        use core::borrow::Borrow;
        unsafe { self.payload.bytes.borrow() }
    }

    pub fn borrow_mut_bytes(&mut self) -> &mut RocList<u8> {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Bytes);
        use core::borrow::BorrowMut;
        unsafe { self.payload.bytes.borrow_mut() }
    }

    pub fn is_bytes(&self) -> bool {
        matches!(self.discriminant, DiscriminantSQLiteValue::Bytes)
    }

    pub fn unwrap_integer(self) -> i64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Integer);
        unsafe { self.payload.integer }
    }

    pub fn borrow_integer(&self) -> i64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Integer);
        unsafe { self.payload.integer }
    }

    pub fn borrow_mut_integer(&mut self) -> &mut i64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Integer);
        unsafe { &mut self.payload.integer }
    }

    pub fn is_integer(&self) -> bool {
        matches!(self.discriminant, DiscriminantSQLiteValue::Integer)
    }

    pub fn is_null(&self) -> bool {
        matches!(self.discriminant, DiscriminantSQLiteValue::Null)
    }

    pub fn unwrap_real(self) -> f64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Real);
        unsafe { self.payload.real }
    }

    pub fn borrow_real(&self) -> f64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Real);
        unsafe { self.payload.real }
    }

    pub fn borrow_mut_real(&mut self) -> &mut f64 {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::Real);
        unsafe { &mut self.payload.real }
    }

    pub fn is_real(&self) -> bool {
        matches!(self.discriminant, DiscriminantSQLiteValue::Real)
    }

    pub fn unwrap_string(mut self) -> roc_std::RocStr {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::String);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.string) }
    }

    pub fn borrow_string(&self) -> &roc_std::RocStr {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::String);
        use core::borrow::Borrow;
        unsafe { self.payload.string.borrow() }
    }

    pub fn borrow_mut_string(&mut self) -> &mut roc_std::RocStr {
        debug_assert_eq!(self.discriminant, DiscriminantSQLiteValue::String);
        use core::borrow::BorrowMut;
        unsafe { self.payload.string.borrow_mut() }
    }

    pub fn is_string(&self) -> bool {
        matches!(self.discriminant, DiscriminantSQLiteValue::String)
    }
}

impl SQLiteValue {
    pub fn bytes(payload: RocList<u8>) -> Self {
        Self {
            discriminant: DiscriminantSQLiteValue::Bytes,
            payload: UnionSQLiteValue {
                bytes: core::mem::ManuallyDrop::new(payload),
            },
        }
    }

    pub fn integer(payload: i64) -> Self {
        Self {
            discriminant: DiscriminantSQLiteValue::Integer,
            payload: UnionSQLiteValue { integer: payload },
        }
    }

    pub fn null() -> Self {
        Self {
            discriminant: DiscriminantSQLiteValue::Null,
            payload: UnionSQLiteValue { null: () },
        }
    }

    pub fn real(payload: f64) -> Self {
        Self {
            discriminant: DiscriminantSQLiteValue::Real,
            payload: UnionSQLiteValue { real: payload },
        }
    }

    pub fn string(payload: roc_std::RocStr) -> Self {
        Self {
            discriminant: DiscriminantSQLiteValue::String,
            payload: UnionSQLiteValue {
                string: core::mem::ManuallyDrop::new(payload),
            },
        }
    }
}

impl Drop for SQLiteValue {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            DiscriminantSQLiteValue::Bytes => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.bytes)
            },
            DiscriminantSQLiteValue::Integer => {}
            DiscriminantSQLiteValue::Null => {}
            DiscriminantSQLiteValue::Real => {}
            DiscriminantSQLiteValue::String => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.string)
            },
        }
    }
}

impl roc_std::RocRefcounted for SQLiteValue {
    fn inc(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantSQLiteValue::Bytes => (*self.payload.bytes).inc(),
                DiscriminantSQLiteValue::Integer => {}
                DiscriminantSQLiteValue::Null => {}
                DiscriminantSQLiteValue::Real => {}
                DiscriminantSQLiteValue::String => (*self.payload.string).inc(),
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantSQLiteValue::Bytes => (*self.payload.bytes).dec(),
                DiscriminantSQLiteValue::Integer => {}
                DiscriminantSQLiteValue::Null => {}
                DiscriminantSQLiteValue::Real => {}
                DiscriminantSQLiteValue::String => (*self.payload.string).dec(),
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Debug, PartialEq, PartialOrd)]
#[repr(C)]
pub struct SQLiteBindings {
    pub name: roc_std::RocStr,
    pub value: SQLiteValue,
}

impl roc_std::RocRefcounted for SQLiteBindings {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl sqlite::Bindable for &SQLiteBindings {
    fn bind(self, stmt: &mut sqlite::Statement) -> sqlite::Result<()> {
        match self.value.discriminant() {
            DiscriminantSQLiteValue::Bytes => {
                stmt.bind((self.name.as_str(), self.value.borrow_bytes().as_slice()))
            }
            DiscriminantSQLiteValue::Integer => {
                stmt.bind((self.name.as_str(), self.value.borrow_integer()))
            }
            DiscriminantSQLiteValue::Real => {
                stmt.bind((self.name.as_str(), self.value.borrow_real()))
            }
            DiscriminantSQLiteValue::String => {
                stmt.bind((self.name.as_str(), self.value.borrow_string().as_str()))
            }
            DiscriminantSQLiteValue::Null => stmt.bind((self.name.as_str(), sqlite::Value::Null)),
        }
    }
}
