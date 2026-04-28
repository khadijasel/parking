<?php

namespace App\Http\Requests\Owner;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateBusinessSettingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'workingDays' => ['required', 'array', 'min:1'],
            'workingDays.*' => [
                'required',
                Rule::in([
                    'MONDAY',
                    'TUESDAY',
                    'WEDNESDAY',
                    'THURSDAY',
                    'FRIDAY',
                    'SATURDAY',
                    'SUNDAY',
                ]),
            ],
            'openingTime' => ['required', 'date_format:H:i'],
            'closingTime' => ['required', 'date_format:H:i', 'different:openingTime'],
            'pricing' => ['required', 'array'],
            'pricing.hourlyRateDzd' => ['required', 'numeric', 'min:0'],
            'pricing.dailyRateDzd' => ['required', 'numeric', 'min:0'],
            'pricing.monthlyRateDzd' => ['nullable', 'numeric', 'min:0'],
        ];
    }
}
