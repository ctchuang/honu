//! The services microapps share, handed to them in their `Context`: for now,
//! the key for asking Claude.

/// Storage key for the Claude API key the web version asks for. The desktop
/// version reads `ANTHROPIC_API_KEY` from `.env` instead and stores nothing.
#[cfg(target_arch = "wasm32")]
const API_KEY_KEY: &str = "anthropic_api_key";

pub struct Services {
    pub api_key: ApiKey,
}

impl Services {
    /// The services as they were left: the API key from `.env` on the
    /// desktop, or from the browser's local storage on the web.
    pub fn load(storage: Option<&dyn eframe::Storage>) -> Self {
        Self {
            api_key: ApiKey::new(initial_api_key(storage)),
        }
    }

    /// Services with just `key`, for tests.
    #[cfg(test)]
    pub fn with_api_key(key: Option<&str>) -> Self {
        Self {
            api_key: ApiKey::new(key.map(str::to_owned)),
        }
    }

    /// Keeps what changed since the last call, such as a key entered or
    /// refused, for the next launch.
    pub fn store(&mut self, storage: Option<&mut (dyn eframe::Storage + 'static)>) {
        if let Some(key) = self.api_key.take_change() {
            remember_api_key(storage, key);
        }
    }
}

/// The key for asking Claude, once known. It notes when it changes, so the
/// change can be stored.
pub struct ApiKey {
    key: Option<String>,
    changed: bool,
}

impl ApiKey {
    pub fn new(key: Option<String>) -> Self {
        Self {
            key,
            changed: false,
        }
    }

    pub fn get(&self) -> Option<&str> {
        self.key.as_deref()
    }

    /// Takes a key the user entered.
    pub fn set(&mut self, key: String) {
        self.key = Some(key);
        self.changed = true;
    }

    /// Forgets a key the API refused.
    pub fn clear(&mut self) {
        self.key = None;
        self.changed = true;
    }

    /// The key as it is now, if it changed since the last call.
    fn take_change(&mut self) -> Option<Option<&str>> {
        std::mem::take(&mut self.changed).then_some(self.key.as_deref())
    }
}

/// The desktop version takes the key from `ANTHROPIC_API_KEY`, which may be
/// set in a `.env` file in or above the working directory.
#[cfg(not(target_arch = "wasm32"))]
fn initial_api_key(_storage: Option<&dyn eframe::Storage>) -> Option<String> {
    dotenvy::dotenv().ok();
    std::env::var("ANTHROPIC_API_KEY")
        .ok()
        .filter(|key| !key.trim().is_empty())
}

/// The web version uses the key pasted into an Ask bubble earlier, kept in
/// the browser's local storage.
#[cfg(target_arch = "wasm32")]
fn initial_api_key(storage: Option<&dyn eframe::Storage>) -> Option<String> {
    storage.and_then(|storage| storage.get_string(API_KEY_KEY))
}

/// Saves a key just pasted into an Ask bubble, or forgets one the API
/// refused. Only the web version keeps it; the desktop version forgets it on
/// quit, so it never lands in a file.
#[cfg(target_arch = "wasm32")]
fn remember_api_key(storage: Option<&mut (dyn eframe::Storage + 'static)>, key: Option<&str>) {
    let Some(storage) = storage else {
        return;
    };
    match key {
        Some(key) => storage.set_string(API_KEY_KEY, key.to_owned()),
        None => storage.remove_string(API_KEY_KEY),
    }
    storage.flush();
}

#[cfg(not(target_arch = "wasm32"))]
fn remember_api_key(_storage: Option<&mut (dyn eframe::Storage + 'static)>, _key: Option<&str>) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_key_reports_each_change_once() {
        let mut key = ApiKey::new(Some("from-env".to_owned()));
        assert_eq!(key.get(), Some("from-env"));
        assert_eq!(key.take_change(), None, "loading is not a change");

        key.set("pasted".to_owned());
        assert_eq!(key.take_change(), Some(Some("pasted")));
        assert_eq!(key.take_change(), None);

        key.clear();
        assert_eq!(key.get(), None);
        assert_eq!(key.take_change(), Some(None));
    }
}
