#!/usr/bin/env python3
"""Convertit un fichier de contenu au format texte léger vers les blocs JSON
importables dans l'app de fiches (espèces, historiques, classes, sous-classes,
dons). Génère un tableau JSON par type, prêt à coller dans la fenêtre
« Importer » (en choisissant le type correspondant dans le menu déroulant).

Usage :
    python3 convertir_contenu.py mon-contenu.txt
    python3 convertir_contenu.py mon-contenu.txt --lib /chemin/vers/projet

L'option --lib pointe vers le dossier contenant les srd-2024-*.json (et
éventuellement custom-content.json). Elle sert à résoudre les RÉFÉRENCES :
  • la classe parente d'une sous-classe  -> son vrai id ;
  • le don d'origine d'un historique      -> son vrai id.
Sans --lib, ces références sont devinées par slug et signalées en avertissement.

Le contenu transcrit doit provenir d'un livre que VOUS possédez, et les
descriptions doivent être des RÉSUMÉS reformulés (pas le texte intégral).
"""
import argparse, json, re, sys, unicodedata
from pathlib import Path

# --- Tables de référence (collées sur les modèles Swift) -------------------

ABILITIES = ["FOR", "DEX", "CON", "INT", "SAG", "CHA"]

SKILLS = ["Acrobaties", "Arcanes", "Athlétisme", "Discrétion", "Dressage",
          "Escamotage", "Histoire", "Intimidation", "Intuition", "Investigation",
          "Médecine", "Nature", "Perception", "Persuasion", "Religion",
          "Représentation", "Survie", "Tromperie"]

CASTER_TYPES = {"none", "full", "half", "third", "pact"}

# Catégories de don : synonymes tolérés -> valeur canonique.
FEAT_CATEGORIES = {
    "general": "general", "général": "general",
    "origine": "origine", "origin": "origine",
    "style": "styleDeCombat", "stylededecombat": "styleDeCombat",
    "styledecombat": "styleDeCombat", "styledecombat": "styleDeCombat",
    "faveur": "faveurEpique", "faveurepique": "faveurEpique",
    "epique": "faveurEpique", "épique": "faveurEpique",
}

# Classes SRD : noms (FR/EN) -> id réel embarqué. Sert à résoudre la classe
# parente d'une sous-classe sans avoir à connaître les id par cœur.
SRD_CLASS_IDS = {
    "barbarian": "srd-2024_barbarian", "barbare": "srd-2024_barbarian",
    "bard": "srd-2024_bard", "barde": "srd-2024_bard",
    "cleric": "srd-2024_cleric", "clerc": "srd-2024_cleric",
    "druid": "srd-2024_druid", "druide": "srd-2024_druid",
    "fighter": "srd-2024_fighter", "guerrier": "srd-2024_fighter",
    "monk": "srd-2024_monk", "moine": "srd-2024_monk",
    "paladin": "srd-2024_paladin",
    "ranger": "srd-2024_ranger", "rôdeur": "srd-2024_ranger", "rodeur": "srd-2024_ranger",
    "rogue": "srd-2024_rogue", "roublard": "srd-2024_rogue", "voleur": "srd-2024_rogue",
    "sorcerer": "srd-2024_sorcerer", "ensorceleur": "srd-2024_sorcerer",
    "warlock": "srd-2024_warlock", "occultiste": "srd-2024_warlock", "démoniste": "srd-2024_warlock",
    "wizard": "srd-2024_wizard", "magicien": "srd-2024_wizard",
}

# Préfixes d'id par type (mêmes que ceux générés par l'éditeur Swift).
ID_PREFIX = {"espece": "esp", "historique": "hist", "classe": "classe",
             "sousclasse": "sousclasse", "don": "don"}

warnings = []
def warn(msg): warnings.append(msg)


# --- Utilitaires ------------------------------------------------------------

def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")

def slug(name):
    base = re.sub(r"[^a-z0-9]+", "-", strip_accents(name).lower()).strip("-")
    return base or "sans-nom"

def make_id(name, kind):
    return f"{ID_PREFIX[kind]}-{slug(name)}"

def split_list(value):
    return [x.strip() for x in value.split(",") if x.strip()]

def canon_ability(tok, ctx):
    t = tok.strip().upper()
    if t in ABILITIES:
        return t
    warn(f"[{ctx}] caractéristique inconnue : « {tok} » (attendu : {', '.join(ABILITIES)})")
    return None

def canon_skill(tok, ctx):
    folded = strip_accents(tok).strip().lower()
    for s in SKILLS:
        if strip_accents(s).lower() == folded:
            return s  # renvoie la forme accentuée canonique
    warn(f"[{ctx}] compétence inconnue : « {tok} »")
    return None

def parse_feature(value, ctx, with_level):
    """« Nom (niveau) | description » -> (name, level|None, description)."""
    parts = value.split("|", 1)
    head = parts[0].strip()
    desc = parts[1].strip() if len(parts) > 1 else ""
    level = None
    m = re.search(r"\((\d+)\)\s*$", head)
    if m:
        level = int(m.group(1))
        head = head[:m.start()].strip()
    if with_level and level is None:
        level = 1
        warn(f"[{ctx}] capacité « {head} » sans niveau -> niveau 1 par défaut.")
    return head, level, desc


# --- Résolution des références via la bibliothèque (--lib) -------------------

class RefIndex:
    def __init__(self, lib_dir):
        self.class_by_name = dict(SRD_CLASS_IDS)  # base : classes SRD
        self.feat_by_name = {}
        if not lib_dir:
            return
        d = Path(lib_dir)
        self._load_classes(d / "srd-2024-classes.json")
        self._load_feats(d / "srd-2024-feats.json")
        self._load_custom(d / "custom-content.json")

    def _index(self, target, name, _id):
        target[strip_accents(name).lower()] = _id

    def _load_classes(self, path):
        for c in self._read(path):
            self._index(self.class_by_name, c.get("name", ""), c["id"])

    def _load_feats(self, path):
        for f in self._read(path):
            self._index(self.feat_by_name, f.get("name", ""), f["id"])

    def _load_custom(self, path):
        data = self._read_obj(path)
        for c in data.get("classes", []):
            self._index(self.class_by_name, c.get("name", ""), c["id"])
        for f in data.get("feats", []):
            self._index(self.feat_by_name, f.get("name", ""), f["id"])

    @staticmethod
    def _read(path):
        try:
            return json.loads(Path(path).read_text(encoding="utf-8"))
        except Exception:
            return []

    @staticmethod
    def _read_obj(path):
        try:
            return json.loads(Path(path).read_text(encoding="utf-8"))
        except Exception:
            return {}

    def resolve_class(self, token, ctx):
        key = strip_accents(token).strip().lower()
        if key in self.class_by_name:
            return self.class_by_name[key]
        guess = make_id(token, "classe")
        warn(f"[{ctx}] classe parente « {token} » non trouvée -> id deviné « {guess} » "
             f"(vérifiez, ou utilisez --lib).")
        return guess

    def resolve_feat(self, token, ctx):
        key = strip_accents(token).strip().lower()
        if key in self.feat_by_name:
            return self.feat_by_name[key]
        guess = make_id(token, "don")
        warn(f"[{ctx}] don d'origine « {token} » non trouvé -> id deviné « {guess} » "
             f"(vérifiez, ou utilisez --lib).")
        return guess


# --- Analyse du fichier source ----------------------------------------------

# Un en-tête de bloc commence en DÉBUT DE LIGNE, sans indentation. Les champs,
# eux, sont toujours indentés — ce qui évite que « don: … » (champ d'historique)
# soit confondu avec un en-tête de bloc « DON: … ».
BLOCK_RE = re.compile(r"^(ESPECE|ESPÈCE|HISTORIQUE|CLASSE|SOUSCLASSE|SOUS-CLASSE|DON)\s*:\s*(.+)$",
                      re.IGNORECASE)
KIND_NORM = {"espece": "espece", "espèce": "espece", "historique": "historique",
             "classe": "classe", "sousclasse": "sousclasse", "sous-classe": "sousclasse",
             "don": "don"}

def parse_source(text):
    """Renvoie une liste de blocs : (kind, name, [(key, value), ...])."""
    blocks = []
    current = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        m = BLOCK_RE.match(line)
        if m:
            kind = KIND_NORM[m.group(1).lower()]
            current = (kind, m.group(2).strip(), [])
            blocks.append(current)
            continue
        if current is None:
            warn(f"Ligne hors bloc ignorée : « {line.strip()} »")
            continue
        if ":" in line:
            key, value = line.split(":", 1)
            current[2].append((key.strip().lower(), value.strip()))
        else:
            warn(f"Ligne sans « clé: valeur » ignorée : « {line.strip()} »")
    return blocks


# --- Construction des objets par type ---------------------------------------

def build(blocks, refs):
    out = {"espece": [], "historique": [], "classe": [], "sousclasse": [], "don": []}
    for kind, name, fields in blocks:
        ctx = f"{kind} « {name} »"
        fd = {}            # champs simples (dernière valeur gagne)
        traits = []        # capacités/traits répétables
        for key, value in fields:
            if key in ("trait", "capacite", "capacité"):
                traits.append(value)
            else:
                fd[key] = value

        if kind == "espece":
            out["espece"].append({
                "id": make_id(name, "espece"), "name": name,
                "traits": [trait_obj(parse_feature(v, ctx, with_level=False)) for v in traits],
                "isCustom": True,
            })
        elif kind == "historique":
            feat = fd.get("don", "").strip()
            out["historique"].append({
                "id": make_id(name, "historique"), "name": name,
                "abilityOptions": [a for a in (canon_ability(t, ctx) for t in split_list(fd.get("caracs", ""))) if a],
                "skillProficiencies": [s for s in (canon_skill(t, ctx) for t in split_list(fd.get("competences", ""))) if s],
                "originFeatId": refs.resolve_feat(feat, ctx) if feat and feat != "—" else None,
                "toolProficiency": fd.get("outil", ""),
                "equipmentText": fd.get("equipement", fd.get("équipement", "")),
                "isCustom": True,
            })
        elif kind == "classe":
            caster = fd.get("lanceur", "none").strip().lower()
            if caster not in CASTER_TYPES:
                warn(f"[{ctx}] type de lanceur inconnu « {caster} » -> none."); caster = "none"
            spell = fd.get("carac_sorts", "").strip()
            spell_ab = None if spell.lower() in ("", "aucune", "—") else canon_ability(spell, ctx)
            out["classe"].append({
                "id": make_id(name, "classe"), "name": name,
                "hitDie": fd.get("de", fd.get("dé", "d8")),
                "saveProficiencies": [a for a in (canon_ability(t, ctx) for t in split_list(fd.get("saves", ""))) if a],
                "casterType": caster,
                "spellcastingAbility": spell_ab,
                "skillChoiceCount": int_or(fd.get("competences_nb", "2"), 2, ctx),
                "skillChoiceOptions": [s for s in (canon_skill(t, ctx) for t in split_list(fd.get("competences_choix", ""))) if s],
                "asiLevels": [n for n in (int_or(t, None, ctx) for t in split_list(fd.get("asi", "4, 8, 12, 16, 19"))) if n],
                "features": [trait_obj(parse_feature(v, ctx, with_level=True)) for v in traits],
                "isCustom": True,
            })
        elif kind == "sousclasse":
            parent_token = parent_in_parens(name)
            display = re.sub(r"\s*\([^)]*\)\s*$", "", name).strip()
            out["sousclasse"].append({
                "id": make_id(display, "sousclasse"), "name": display,
                "parentClassId": refs.resolve_class(parent_token, ctx) if parent_token else "",
                "features": [trait_obj(parse_feature(v, ctx, with_level=True)) for v in traits],
                "isCustom": True,
            })
            if not parent_token:
                warn(f"[{ctx}] pas de classe parente entre parenthèses (ex. « Champion (Guerrier) »).")
        elif kind == "don":
            cat_raw = strip_accents(fd.get("categorie", fd.get("catégorie", "general"))).lower().replace(" ", "")
            cat = FEAT_CATEGORIES.get(cat_raw, "general")
            if cat_raw not in FEAT_CATEGORIES:
                warn(f"[{ctx}] catégorie inconnue « {fd.get('categorie','')} » -> general.")
            prereq = fd.get("prerequis", fd.get("prérequis", "")).strip()
            out["don"].append({
                "id": make_id(name, "don"), "name": name, "category": cat,
                "shortEffect": fd.get("effet", ""),
                "prerequisite": "" if prereq in ("—", "-") else prereq,
                "isCustom": True,
            })
    return out


def trait_obj(parsed):
    name, level, desc = parsed
    o = {"name": name, "description": desc}
    if level is not None:
        o["level"] = level
    return o

def parent_in_parens(name):
    m = re.search(r"\(([^)]*)\)\s*$", name)
    return m.group(1).strip() if m else None

def int_or(s, default, ctx):
    try:
        return int(str(s).strip())
    except ValueError:
        if default is not None:
            warn(f"[{ctx}] nombre attendu, lu « {s} » -> {default}.")
        return default


# --- Détection des collisions d'id ------------------------------------------

def check_duplicates(out):
    for kind, items in out.items():
        seen = {}
        for it in items:
            seen.setdefault(it["id"], []).append(it["name"])
        for _id, names in seen.items():
            if len(names) > 1:
                warn(f"[{kind}] id en double « {_id} » pour : {', '.join(names)} "
                     f"(l'import écrasera les précédents).")


# --- Programme principal -----------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Convertit le format texte léger en JSON importable.")
    ap.add_argument("source", help="fichier texte à convertir")
    ap.add_argument("--lib", help="dossier des srd-2024-*.json (résolution des références)")
    ap.add_argument("--out", default=".", help="dossier de sortie (défaut : courant)")
    args = ap.parse_args()

    text = Path(args.source).read_text(encoding="utf-8")
    refs = RefIndex(args.lib)
    blocks = parse_source(text)
    out = build(blocks, refs)
    check_duplicates(out)

    names = {"espece": "especes", "historique": "historiques", "classe": "classes",
             "sousclasse": "sousclasses", "don": "dons"}
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    print("Résultat :")
    for kind, items in out.items():
        if not items:
            continue
        path = outdir / f"import-{names[kind]}.json"
        path.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  {len(items):3d}  {names[kind]:14s} -> {path}")

    if warnings:
        print(f"\n⚠️  {len(warnings)} avertissement·s :")
        for w in warnings:
            print("   -", w)
    else:
        print("\n✓ Aucun avertissement.")

    print("\nÀ faire : dans l'app, fenêtre « Importer », choisissez le type dans le menu,")
    print("puis collez le contenu du fichier import-<type>.json correspondant.")


if __name__ == "__main__":
    main()
