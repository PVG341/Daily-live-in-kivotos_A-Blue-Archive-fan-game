class_name StudentData
extends Resource

enum CombatRole {
	TANKER,
	DAMAGE_DEALER,
	HEALER,
	BUFFER
}

enum SquadSlot {
	STRIKER,
	SPECIAL
}

@export var id: String = ""
@export var student_name: String = ""
@export var role: CombatRole = CombatRole.DAMAGE_DEALER
@export var squad_slot: SquadSlot = SquadSlot.STRIKER
@export var normal_model_path: String = ""
@export var chibi_model_path: String = ""
@export var bond_level: int = 1
@export var bond_exp: int = 0
@export var base_hp: int = 1000
@export var base_atk: int = 100
@export var base_def: int = 50
@export var base_speed: float = 5.0
@export var attack_range: float = 10.0
@export var attack_type: String = "HITSCAN" # HITSCAN, PROJECTILE
@export var skills: Array[SkillData] = []
@export var favorite_food: String = ""
@export var favorite_gift: String = ""
