<?php

// Autorise le dashboard Vue (servi depuis un autre domaine) à appeler l'API.
// L'auth admin/owner utilise des tokens Bearer (localStorage), pas des cookies,
// donc on peut autoriser toutes les origines sans `supports_credentials`.
return [

    'paths' => ['api/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => ['*'],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
