#!/usr/bin/env python3
"""Importe le contenu « personnage » du SRD 2024 (SRD 5.2) depuis l'API Open5e V2
et le convertit vers nos formats (Species, Background, CharacterClass, Subclass, Feat).

Source : https://api.open5e.com/v2/{classes,species,backgrounds,feats}/?document__key__in=srd-2024
Licence des données : CC-BY-4.0 (SRD 5.2, Wizards of the Coast).

L'API fournit : dé de vie, type de lanceur, sauvegardes, features (avec niveau via
`gained_at`), traits d'espèce, et les `benefits` d'historique. Elle NE fournit PAS :
la carac d'incantation, les listes de compétences au choix par classe, ni les niveaux
d'amélioration de caractéristique → codés en dur ci-dessous (tables connues du SRD).
"""
import json, re, subprocess

BASE = "https://api.open5e.com/v2"
DOC = "srd-2024"

# --- Correspondances anglais -> nos codes -------------------------------------

ABIL_EN = {"Strength": "FOR", "Dexterity": "DEX", "Constitution": "CON",
           "Intelligence": "INT", "Wisdom": "SAG", "Charisma": "CHA"}

EN_SKILL = {
    "Acrobatics": "Acrobaties", "Animal Handling": "Dressage", "Arcana": "Arcanes",
    "Athletics": "Athlétisme", "Deception": "Tromperie", "History": "Histoire",
    "Insight": "Intuition", "Intimidation": "Intimidation", "Investigation": "Investigation",
    "Medicine": "Médecine", "Nature": "Nature", "Perception": "Perception",
    "Performance": "Représentation", "Persuasion": "Persuasion", "Religion": "Religion",
    "Sleight of Hand": "Escamotage", "Stealth": "Discrétion", "Survival": "Survie",
}
ALL18 = list(EN_SKILL.keys())

CATEGORY = {"General": "general", "Origin": "origine",
            "Fighting Style": "styleDeCombat", "Epic Boon": "faveurEpique"}

# --- Tables non fournies par l'API (connues du SRD 2024) ----------------------

SPELL_ABILITY = {"bard": "CHA", "cleric": "SAG", "druid": "SAG", "sorcerer": "CHA",
                 "warlock": "CHA", "wizard": "INT", "paladin": "CHA", "ranger": "SAG"}

ASI_LEVELS = {"fighter": [4, 6, 8, 12, 14, 16, 19], "rogue": [4, 8, 10, 12, 16, 19]}
ASI_DEFAULT = [4, 8, 12, 16, 19]

SKILL_CHOICES = {  # classe -> (nombre, options en anglais)
    "barbarian": (2, ["Animal Handling", "Athletics", "Intimidation", "Nature", "Perception", "Survival"]),
    "bard":      (3, ALL18),
    "cleric":    (2, ["History", "Insight", "Medicine", "Persuasion", "Religion"]),
    "druid":     (2, ["Arcana", "Animal Handling", "Insight", "Medicine", "Nature", "Perception", "Religion", "Survival"]),
    "fighter":   (2, ["Acrobatics", "Animal Handling", "Athletics", "History", "Insight", "Intimidation", "Perception", "Persuasion", "Survival"]),
    "monk":      (2, ["Acrobatics", "Athletics", "History", "Insight", "Religion", "Stealth"]),
    "paladin":   (2, ["Athletics", "Insight", "Intimidation", "Medicine", "Persuasion", "Religion"]),
    "ranger":    (3, ["Animal Handling", "Athletics", "Insight", "Investigation", "Nature", "Perception", "Stealth", "Survival"]),
    "rogue":     (4, ["Acrobatics", "Athletics", "Deception", "Insight", "Intimidation", "Investigation", "Perception", "Performance", "Persuasion", "Sleight of Hand", "Stealth"]),
    "sorcerer":  (2, ["Arcana", "Deception", "Insight", "Intimidation", "Persuasion", "Religion"]),
    "warlock":   (2, ["Arcana", "Deception", "History", "Intimidation", "Investigation", "Nature", "Religion"]),
    "wizard":    (2, ["Arcana", "History", "Insight", "Investigation", "Medicine", "Nature", "Religion"]),
}

# --- Texte --------------------------------------------------------------------

def clean(text):
    if not text:
        return ""
    t = re.sub(r"[*_`#]+", "", text)            # retire le markdown léger
    t = re.sub(r"\s+", " ", t)                  # espaces compactés
    return t.strip()

def short(text, n=220):
    t = clean(text)
    if len(t) <= n:
        return t
    cut = t[:n].rsplit(" ", 1)[0]
    return cut + "…"

def skills_fr(names):
    return [EN_SKILL[s] for s in names if s in EN_SKILL]

def parse_skills(desc):
    parts = re.split(r",|\band\b|&", desc or "")
    return [EN_SKILL[p.strip()] for p in parts if p.strip() in EN_SKILL]

def parse_abilities(desc):
    parts = re.split(r",|\band\b|/", desc or "")
    return [ABIL_EN[p.strip()] for p in parts if p.strip() in ABIL_EN]

def feature_level(f):
    levels = [e.get("level") for e in (f.get("gained_at") or [])
              if isinstance(e, dict) and isinstance(e.get("level"), int)]
    return min(levels) if levels else 1

def map_features(raw):
    """Vraies capacités de classe / sous-classe -> Trait avec `level`.
    On ne garde que `CLASS_LEVEL_FEATURE` (le reste = données de table : slots,
    bonus de maîtrise, etc.), et on écarte l'ASI (géré par l'éditeur)."""
    out = {}
    for f in raw or []:
        if f.get("feature_type") != "CLASS_LEVEL_FEATURE":
            continue
        name = (f.get("name") or "").strip()
        if name == "Ability Score Improvement" or "Spell List" in name:
            continue
        desc = clean(f.get("desc"))
        if not desc:
            continue
        lvl = feature_level(f)
        if name not in out or lvl < out[name]["level"]:
            out[name] = {"name": name, "description": short(desc), "level": lvl}
    return sorted(out.values(), key=lambda x: (x["level"], x["name"]))

# --- Récupération -------------------------------------------------------------

def fetch(endpoint):
    items, page = [], 1
    while True:
        url = f"{BASE}/{endpoint}/?document__key__in={DOC}&limit=100&page={page}"
        r = subprocess.run(["curl", "-s", "-m", "60", url], capture_output=True, text=True)
        d = json.loads(r.stdout)
        items += d.get("results") or []
        if not d.get("next"):
            break
        page += 1
    return items

def fetch_tools():
    """Items srd-2024 de catégorie « Tools », hors variantes de jeux (Gaming Set)."""
    items = fetch("items")
    return [i for i in items
            if (i.get("category") or {}).get("name") == "Tools"
            and not i["name"].startswith("Gaming Set")]

# --- Mappage ------------------------------------------------------------------

def map_species(s):
    traits = [{"name": (t.get("name") or "").strip(), "description": short(t.get("desc"))}
              for t in (s.get("traits") or [])]
    return {"id": s["key"], "name": s["name"], "traits": traits, "isCustom": False}

def feat_effect(f):
    bens = [clean(b.get("desc")) for b in (f.get("benefits") or []) if clean(b.get("desc"))]
    return short(" ".join(bens), 220) if bens else short(f.get("desc"), 200)

def map_feat(f):
    return {"id": f["key"], "name": f["name"],
            "category": CATEGORY.get(f.get("type"), "general"),
            "shortEffect": feat_effect(f), "isCustom": False}

def map_background(b, feat_by_name):
    bens = {x.get("type"): x for x in (b.get("benefits") or [])}
    feat_desc = (bens.get("feat") or {}).get("desc", "")
    feat_name = re.split(r"\(", feat_desc)[0].strip()
    return {
        "id": b["key"], "name": b["name"],
        "abilityOptions": parse_abilities((bens.get("ability_score") or {}).get("desc", "")),
        "skillProficiencies": parse_skills((bens.get("skill_proficiency") or {}).get("desc", "")),
        "originFeatId": feat_by_name.get(feat_name.lower()),
        "toolProficiency": clean((bens.get("tool_proficiency") or {}).get("desc", "")),
        "equipmentText": short((bens.get("equipment") or {}).get("desc", ""), 300),
        "isCustom": False,
    }

def map_class(c):
    key = c["name"].lower()
    count, opts = SKILL_CHOICES.get(key, (2, ALL18))
    return {
        "id": c["key"], "name": c["name"],
        "hitDie": (c.get("hit_dice") or "").lower(),
        "saveProficiencies": [ABIL_EN[s["name"]] for s in (c.get("saving_throws") or []) if s.get("name") in ABIL_EN],
        "casterType": (c.get("caster_type") or "NONE").lower(),
        "spellcastingAbility": SPELL_ABILITY.get(key),
        "skillChoiceCount": count,
        "skillChoiceOptions": skills_fr(opts),
        "asiLevels": ASI_LEVELS.get(key, ASI_DEFAULT),
        "cantripsKnownByLevel": class_table(c, "Cantrips"),
        "preparedSpellsByLevel": class_table(c, "Prepared Spells"),
        "features": map_features(c.get("features")),
        "isCustom": False,
    }

def map_subclass(c):
    parent = (c.get("subclass_of") or {}).get("key", "")
    return {"id": c["key"], "name": c["name"], "parentClassId": parent,
            "features": map_features(c.get("features")), "isCustom": False}

def map_spell(s):
    """Sort « léger » : nom + niveau + classes (clés = id de nos classes), sans description."""
    return {"id": s["key"], "name": s["name"], "level": s.get("level") or 0,
            "classIds": [c["key"] for c in (s.get("classes") or [])], "isCustom": False}

TOOL_KIT_NAMES = {"Climber's Kit", "Disguise Kit", "Forgery Kit", "Healer's Kit",
                  "Herbalism Kit", "Poisoner's Kit"}

def tool_category(raw_name):
    if raw_name.startswith("Musical Instrument"):
        return "instrument"
    if raw_name in TOOL_KIT_NAMES:
        return "kit"
    return "artisan"   # inclut aussi Outils de voleur / de navigateur (pas de 4e bac)

def tool_clean_name(raw_name):
    """« Musical Instrument, Lute » -> « Lute » ; « Carpenter's Tools (8 GP) » -> « Carpenter's Tools »."""
    name = re.sub(r"\s*\(\d+\s*GP\)\s*$", "", raw_name)
    if name.startswith("Musical Instrument, "):
        name = name[len("Musical Instrument, "):]
    return name.strip()

def map_tool(t):
    """Outil « léger » : nom nettoyé + catégorie, sans description ni coût.
    Les variantes de jeux (« Gaming Set, … ») sont exclues en amont (fetch_tools)."""
    name = tool_clean_name(t["name"])
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return {"id": f"srd-2024_tool_{slug}", "name": name,
            "category": tool_category(t["name"]), "isCustom": False}

def class_table(c, column):
    """Extrait une colonne de table de classe (ex. « Cantrips », « Prepared Spells »)
    en tableau de 20 entiers (niveaux 1→20), report de la dernière valeur si trou.
    Renvoie [] si la classe n'a pas cette colonne (non-lanceur, demi-lanceur sans tours)."""
    for f in c.get("features") or []:
        if f.get("feature_type") == "CLASS_TABLE_DATA" and f.get("name") == column:
            by_level = {e["level"]: e["column_value"] for e in (f.get("data_for_class_table") or [])}
            out, last = [], 0
            for lvl in range(1, 21):
                if lvl in by_level:
                    try: last = int(by_level[lvl])
                    except (TypeError, ValueError): pass
                out.append(last)
            return out
    return []

def dump(name, data):
    with open(name, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

def main():
    raw_classes = fetch("classes")
    species = sorted((map_species(s) for s in fetch("species")), key=lambda x: x["name"])
    feats = sorted((map_feat(f) for f in fetch("feats") if f["name"] != "Ability Score Improvement"),
                   key=lambda x: x["name"])
    feat_by_name = {f["name"].split("(")[0].strip().lower(): f["id"] for f in feats}
    backgrounds = sorted((map_background(b, feat_by_name) for b in fetch("backgrounds")), key=lambda x: x["name"])

    base = sorted((map_class(c) for c in raw_classes if not c.get("subclass_of")), key=lambda x: x["name"])
    subs = sorted((map_subclass(c) for c in raw_classes if c.get("subclass_of")), key=lambda x: x["name"])
    spells = sorted((map_spell(s) for s in fetch("spells")), key=lambda x: (x["level"], x["name"]))
    tools = sorted((map_tool(t) for t in fetch_tools()), key=lambda x: (x["category"], x["name"]))

    dump("srd-2024-species.json", species)
    dump("srd-2024-backgrounds.json", backgrounds)
    dump("srd-2024-classes.json", base)
    dump("srd-2024-subclasses.json", subs)
    dump("srd-2024-feats.json", feats)
    dump("srd-2024-spells.json", spells)
    dump("srd-2024-tools.json", tools)

    print(f"espèces      : {len(species)}")
    print(f"historiques  : {len(backgrounds)}")
    print(f"classes      : {len(base)}")
    print(f"sous-classes : {len(subs)}")
    print(f"dons         : {len(feats)}")
    print(f"sorts        : {len(spells)}")
    print(f"outils       : {len(tools)}")

if __name__ == "__main__":
    main()
