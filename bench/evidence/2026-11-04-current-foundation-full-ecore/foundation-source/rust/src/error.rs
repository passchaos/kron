use std::fmt;
use std::io;

#[derive(Debug)]
pub enum Error {
    InvalidInput(String),
    Io(io::Error),
    Closed,
    QueueFull,
    RecordTooLarge { size: usize, maximum: usize },
    Background(String),
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(message) => formatter.write_str(message),
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Closed => formatter.write_str("logging backend is closed"),
            Self::QueueFull => formatter.write_str("logging queue is full"),
            Self::RecordTooLarge { size, maximum } => {
                write!(
                    formatter,
                    "log record size {size} exceeds maximum {maximum}"
                )
            }
            Self::Background(message) => write!(formatter, "background writer failed: {message}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

pub type Result<T> = std::result::Result<T, Error>;
