<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class OwnerMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! auth('owner')->check()) {
            return response()->json([
                'message' => 'Forbidden. Parking owner access is required.',
            ], 403);
        }

        return $next($request);
    }
}
