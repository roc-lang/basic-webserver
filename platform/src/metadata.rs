
#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(C)]
pub struct InternalMetadata {
    pub headers: roc_std::RocList<roc_app::InternalHeader>,
    pub statusText: roc_std::RocStr,
    pub url: roc_std::RocStr,
    pub statusCode: u16,
}