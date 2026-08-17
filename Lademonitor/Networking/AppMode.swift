import Foundation

/// Ob die App komplett lokal (kein Server, keine HA-Automation, keine Adresssuche
/// ueber den Server-Proxy) oder gegen einen Lademonitor-Server laeuft.
/// `.undecided` gilt nur beim allerersten Start, bevor der Nutzer eine Wahl
/// getroffen hat - siehe ModeSelectionView.
enum AppMode: String, Codable {
    case undecided
    case localOnly
    case server
}
