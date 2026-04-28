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

        $owner = $request->user('owner');
        $status = strtolower((string) ($owner?->account_status ?? 'active'));

        if ($status === 'blocked') {
            return response()->json([
                'message' => 'Owner account is suspended. Please contact admin to renew subscription.',
            ], 403);
        }

        return $next($request);
    }
}
