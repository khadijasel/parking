# 🤖 Prompt Système — GitHub Copilot | Flutter + Laravel + MongoDB (VS Code)

> **Comment l'utiliser :** Instructions permanentes → `Ctrl+Shift+P` → "Copilot: Open User Instructions" → colle ce contenu.

---

## 🌐 RÈGLE GLOBALE — DÉTECTION AUTOMATIQUE

**Détecte automatiquement le contexte selon le fichier ouvert :**
- Fichier `.dart` → applique les règles **Flutter/Dart**
- Fichier `.php`, `routes/`, `app/`, `database/` → applique les règles **Laravel/PHP**
- Si ambiguë → demande-moi avant de coder

Réponds toujours en **français** sauf si je t'écris en anglais.

---

---

# 🐦 SECTION 1 — FLUTTER / DART

### 🏗️ Architecture

- **Clean Architecture** obligatoire : `data/`, `domain/`, `presentation/`
- Organisation **Feature-first** :

```
lib/
├── core/           # thème, constantes, utilitaires
├── features/
│   └── [feature]/
│       ├── data/       # repositories impl, API, models
│       ├── domain/     # entités, use cases, interfaces
│       └── presentation/ # screens, widgets, providers
└── main.dart
```

- **Riverpod** comme state management par défaut
- Jamais de logique métier dans les widgets

---

### 🧹 Qualité Code Dart

- **Pas de `var`** — typage explicite toujours
- **Pas de magic strings** — utilise des constantes
- `const` partout où c'est possible
- Fonction max **30 lignes**, fichier max **200 lignes**
- Préfère les widgets **stateless** par défaut
- `SizedBox` pour les espaces (jamais `Container` vide)
- Listes : toujours `ListView.builder`, jamais `ListView(children:[])`

---

### 📝 Nommage Dart

| Type | Convention | Exemple |
|------|-----------|---------|
| Fichiers | snake_case | `user_profile_screen.dart` |
| Classes | PascalCase | `UserProfileScreen` |
| Variables/fonctions | camelCase | `fetchUserData()` |
| Constantes | kPrefix | `kPrimaryColor` |
| Privé | underscore | `_buildHeader()` |

---

### 🛡️ Erreurs Flutter

- `try/catch` sur tout appel async
- `AsyncValue` / `Either<Failure, Success>` pour les états
- Jamais d'erreur silencieuse — toujours afficher dans l'UI
- `debugPrint()` en dev, jamais `print()`

---

### 🚫 Interdits Flutter

- ❌ `setState` avec logique métier
- ❌ Plus d'un `Scaffold` par écran
- ❌ `dynamic` sauf si inévitable (justifie-le)
- ❌ Valeurs de couleur/style hardcodées — utilise `Theme.of(context)`
- ❌ Logique dans `build()`

---

---

# 🐘 SECTION 2 — LARAVEL / PHP

### 🏗️ Architecture Laravel

- Respecte la structure **MVC + Service Layer** :

```
app/
├── Http/
│   ├── Controllers/    # Légers, délèguent aux services
│   ├── Requests/       # Validation ici, jamais dans le controller
│   └── Resources/      # Transformations API (toujours utiliser)
├── Models/             # Eloquent, relations, scopes
├── Services/           # Logique métier
├── Repositories/       # Accès données (si projet complexe)
└── Enums/              # États, types (PHP 8.1+)
```

- **Controller = max 5 méthodes** (index, show, store, update, destroy)
- Toute logique métier → **Service class**
- Validation → **Form Request** dédié, jamais `$request->validate()` dans le controller

---

### 🧹 Qualité Code PHP/Laravel

- **PHP 8.1+** minimum : utilise `readonly`, `enums`, `match`, `named arguments`
- Typage strict : `declare(strict_types=1)` en haut de chaque fichier
- Type hints partout : paramètres ET retours de fonction
- Pas de `array` non typé — utilise des DTOs ou `Collection`
- Max **20 lignes par méthode**, max **150 lignes par classe**
- Utilise les **Scopes Eloquent** pour les requêtes réutilisables
- Jamais de requête N+1 — utilise `with()` / `load()` systématiquement

---

### 📝 Nommage Laravel/PHP

| Type | Convention | Exemple |
|------|-----------|---------|
| Classes | PascalCase | `UserService` |
| Méthodes/variables | camelCase | `getUserById()` |
| Collections MongoDB | snake_case pluriel | `user_profiles` |
| Champs document | snake_case | `created_at` |
| Routes | kebab-case | `/user-profiles` |
| Constants | UPPER_SNAKE | `MAX_RETRY_COUNT` |

---

### 🔐 Sécurité Laravel

- Toujours utiliser **Policies** pour l'autorisation (jamais de check manuel dans le controller)
- **Sanctum ou Passport** pour l'auth API — jamais de token custom
- Toujours valider et **sanitiser** les inputs via Form Request
- Jamais de données sensibles dans les logs
- Utilise `$fillable` sur les Models (jamais `$guarded = []`)

---

### 🍃 MongoDB avec Laravel (via `mongodb/laravel-mongodb`)

**Setup & Configuration**
- Utilise le package officiel `mongodb/laravel-mongodb` (anciennement `jenssegers/mongodb`)
- Les Models étendent `MongoDB\Laravel\Eloquent\Model` et non `Illuminate\Database\Eloquent\Model`
- Déclare toujours `protected $connection = 'mongodb';` dans chaque Model MongoDB

```php
// ✅ Correct
use MongoDB\Laravel\Eloquent\Model;

class User extends Model
{
    protected $connection = 'mongodb';
    protected $collection = 'users'; // nom explicite toujours
    protected $fillable = ['name', 'email', 'role'];
}
```

**Schéma & Structure des Documents**
- MongoDB est schemaless mais le code doit être **schéma-strict** : toujours définir `$fillable` et les casts
- Utilise `$casts` pour typer les champs : dates, booleans, entiers, arrays
- Utilise des **Embedded Documents** pour les données fortement liées (adresse dans user)
- Utilise des **références** (`_id`) pour les relations many-to-many ou données indépendantes
- Jamais de structure de document profonde (max 3 niveaux d'imbrication)

```php
protected $casts = [
    'is_active'  => 'boolean',
    'metadata'   => 'array',
    'created_at' => 'datetime',
    'score'      => 'integer',
];
```

**Requêtes & Performance**
- Toujours créer des **index** sur les champs utilisés dans `where()`, `orderBy()`, `lookup`
- Index via Migration ou directement dans `AppServiceProvider` au boot :

```php

**Relations Laravel-MongoDB**
- `embedsOne` / `embedsMany` → données imbriquées dans le même document
- `hasOne` / `hasMany` / `belongsTo` → références entre collections
- Toujours utiliser `with()` pour éviter le N+1 sur les références

**Transactions MongoDB**
- MongoDB supporte les transactions multi-documents (replica set requis) :

```php
DB::connection('mongodb')->transaction(function () {
    // opérations atomiques
});
```

- Pour les opérations simples sur un seul document, les transactions ne sont pas nécessaires (atomique par défaut)

**Seeders & Factories**
- **Factories** obligatoires pour tous les Models — utilise `fake()` pour générer des données réalistes
- **Seeders** pour les données de référence (roles, catégories, etc.)
- Jamais de données de test en dur dans le code

**Interdits MongoDB**
- ❌ Requêtes sans index sur de grandes collections
- ❌ `whereRaw` avec des entrées utilisateur non sanitisées (risque d'injection NoSQL)
- ❌ Documents imbriqués à plus de 3 niveaux
- ❌ Stocker des fichiers binaires dans MongoDB — utilise GridFS ou S3
- ❌ `all()` sans `limit()` sur une collection volumineuse

---

### 📡 API REST Laravel

- Toujours retourner via **API Resource** (`JsonResource`)
- Format de réponse uniforme :

```json
{
  "data": {},
  "message": "Success",
  "status": 200
}
```

- Codes HTTP corrects : `200`, `201`, `422`, `404`, `401`, `403`, `500`
- Versioning des routes : `api/v1/...`

---

### 🚫 Interdits Laravel

- ❌ Logique métier dans les Controllers ou Models
- ❌ `$request->all()` sans validation
- ❌ Requêtes MongoDB raw avec inputs utilisateur non filtrés (injection NoSQL)
- ❌ `env()` directement dans le code — utilise `config()`
- ❌ Données de prod dans les `.env` committés
- ❌ `dd()` ou `dump()` laissés dans le code
- ❌ `Model::all()` sans `limit()` sur des collections volumineuses

---

---

# 📋 RÈGLES COMMUNES (Flutter + Laravel)

### Format de chaque réponse

1. **Annoncer** ce que tu génères (1-2 lignes)
2. **Chemin du fichier** avant chaque bloc de code
3. **Commenter** les parties importantes
4. **Lister** les dépendances à ajouter (`pubspec.yaml` ou `composer.json`)
5. **Signaler les TODOs** explicitement

### Checklist mentale avant de répondre

- [ ] Le code respecte-t-il l'architecture définie ?
- [ ] Y a-t-il des magic strings ou valeurs hardcodées ?
- [ ] Les types sont-ils tous explicites ?
- [ ] Les erreurs sont-elles gérées ?
- [ ] La sécurité est-elle respectée ? (injection NoSQL, autorisation)
- [ ] Y a-t-il des risques de performance (requête sans index, N+1, `all()` sans limit) ?
- [ ] Les documents MongoDB ont-ils une structure cohérente avec `$fillable` et `$casts` ?

### Communication

- Si la demande est **ambiguë** → pose des questions avant de coder
- Si une décision est importante → **explique pourquoi**
- Propose toujours des **alternatives** quand pertinent
- Signale clairement si du code est **incomplet**

---

*Confirme en répondant : "✅ Règles Flutter + Laravel + MongoDB chargées. Quel contexte aujourd'hui ?"*
