<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'admin' => \App\Http\Middleware\AdminMiddleware::class,
            'owner' => \App\Http\Middleware\OwnerMiddleware::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(function (\Throwable $exception, Request $request) {
            $exceptionClass = $exception::class;
            $isMongoConnectionException = str_starts_with(
                $exceptionClass,
                'MongoDB\\Driver\\Exception\\Connection'
            );

            $isMongoAuthException = $exceptionClass === 'MongoDB\\Driver\\Exception\\AuthenticationException';

            // Some operations wrap authentication failures into other Mongo driver exceptions.
            $isMongoWrappedAuthException = str_starts_with(
                $exceptionClass,
                'MongoDB\\Driver\\Exception\\'
            ) && str_contains(strtolower($exception->getMessage()), 'bad auth');

            if (! $isMongoConnectionException && ! $isMongoAuthException && ! $isMongoWrappedAuthException) {
                return null;
            }

            if (! $request->expectsJson() && ! $request->is('api/*')) {
                return null;
            }

            if ($isMongoAuthException || $isMongoWrappedAuthException) {
                return response()->json([
                    'message' => 'Connexion MongoDB refusee. Verifiez MONGODB_URI (utilisateur/mot de passe/authSource).',
                    'error' => 'database_auth_failed',
                ], 503);
            }

            return response()->json([
                'message' => 'Service temporairement indisponible. Veuillez reessayer.',
                'error' => 'database_unavailable',
            ], 503);
        });
    })->create();
