<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateOwnerStatusRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'accountStatus' => ['required', Rule::in(['active', 'blocked'])],
            'subscriptionStatus' => ['nullable', Rule::in(['active', 'expired', 'paused'])],
            'reason' => ['nullable', 'string', 'max:255'],
        ];
    }
}
