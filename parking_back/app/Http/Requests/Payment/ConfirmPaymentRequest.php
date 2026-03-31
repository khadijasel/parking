<?php

namespace App\Http\Requests\Payment;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class ConfirmPaymentRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'transaction_id' => ['required', 'string'],
            'method' => ['required', Rule::in(['edahabia', 'cib', 'cash'])],
            'pin' => ['nullable', 'string', 'size:4'],
        ];
    }
}
