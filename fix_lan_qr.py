from pathlib import Path
import re
import sys

LT = chr(60)
GT = chr(62)

TV_FILE = Path(__file__).resolve().parent / "lib" / "screens" / "arena_tv_screen.dart"


def patch_tv_screen(text: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    updated = text

    # 1. Helper LAN URL builder injected inside _ArenaTvScreenState if missing
    if "String _buildLanHunterUrl(" not in updated:
        helper = f"""
  String _lanHostFromWs(String wsUrl) {{
    final Uri? parsed = Uri.tryParse(wsUrl);
    if (parsed != null && parsed.host.isNotEmpty) {{
      return parsed.host;
    }}
    return Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
  }}

  String _buildLanHunterUrl(String roomId, String wsUrl) {{
    final String host = _lanHostFromWs(wsUrl);
    final int port = Uri.base.port != 0 ? Uri.base.port : 8080;
    final String scheme = Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';
    return '$scheme://$host:$port/?mode=lan&role=hunter&room=${{Uri.encodeComponent(roomId)}}&ws=${{Uri.encodeComponent(wsUrl)}}';
  }}

  String _buildLanAdminQr(String roomId, String wsUrl) {{
    return 'shadowburn://admin?mode=lan&room=${{Uri.encodeComponent(roomId)}}&ws=${{Uri.encodeComponent(wsUrl)}}';
  }}
"""
        state_match = re.search(
            rf"class\s+_ArenaTvScreenState\s+extends\s+State{LT}ArenaTvScreen{GT}\s*\{{",
            updated,
        )
        if state_match:
            idx = state_match.end()
            updated = updated[:idx] + helper + updated[idx:]
            notes.append("Ajout des helpers _buildLanHunterUrl et _buildLanAdminQr")

    # 2. Replace hardcoded 192.168.1.8 hunter URLs when wsUrl is present
    pattern_192 = re.compile(
        r"http://192\.168\.1\.8:(\d+)/\?mode=lan&role=hunter&room=([^'\"\s$]+)&ws=([^'\"\s$]+)"
    )
    if pattern_192.search(updated):
        updated = pattern_192.sub(
            r"http://${_lanHostFromWs(\3)}:\1/?mode=lan&role=hunter&room=\2&ws=\3",
            updated,
        )
        notes.append("Remplacement de l'IP codée en dur 192.168.1.8 par _lanHostFromWs")

    # 3. Ensure admin deep-link includes mode=lan and ws when _isLanMode is true
    admin_pattern = re.compile(
        r"(['\"])shadowburn://admin\?room=\$([a-zA-Z0-9_]+)&key=[^'\"]*\1"
    )
    if admin_pattern.search(updated):
        updated = admin_pattern.sub(
            r"(_isLanMode && (_wsUrl ?? '').isNotEmpty) ? _buildLanAdminQr($\2, _wsUrl!) : 'shadowburn://admin?room=$\2&key='",
            updated,
        )
        notes.append("Ajout de mode=lan et ws sur le QR admin en mode LAN")

    return updated, notes


def main() -> int:
    if not TV_FILE.exists():
        print(f"[ERREUR] Fichier introuvable : {TV_FILE}")
        return 1

    original = TV_FILE.read_text(encoding="utf-8")
    patched, notes = patch_tv_screen(original)

    if patched == original:
        print("[INFO] Aucun motif automatique remplacé. Vérifie les lignes QR dans arena_tv_screen.dart.")
        return 0

    backup = TV_FILE.with_suffix(".dart.bak")
    backup.write_text(original, encoding="utf-8", newline="\n")
    TV_FILE.write_text(patched, encoding="utf-8", newline="\n")
    print(f"[OK] {TV_FILE} mis à jour (sauvegarde : {backup.name})")
    for n in notes:
        print(f"  - {n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())