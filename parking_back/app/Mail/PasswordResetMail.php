<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class PasswordResetMail extends Mailable
{
    use Queueable, SerializesModels;

    public function __construct(
        public readonly string $code,
        public readonly string $userName,
    ) {}

    public function envelope(): Envelope
    {
        return new Envelope(
            subject: 'Réinitialisation de votre mot de passe SmartPark',
        );
    }

    public function content(): Content
    {
        return new Content(
            htmlString: $this->buildHtml(),
            text: 'emails.password-reset-plain',
        );
    }

    private function buildHtml(): string
    {
        $name = e($this->userName);
        $code = e($this->code);

        return <<<HTML
        <!DOCTYPE html>
        <html lang="fr">
        <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
        <body style="margin:0;padding:0;background:#f5f5f5;font-family:Arial,sans-serif;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f5;padding:40px 0;">
            <tr><td align="center">
              <table width="520" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.08);">
                <tr><td style="background:#1a7a4a;padding:28px 32px;text-align:center;">
                  <span style="color:#ffffff;font-size:22px;font-weight:700;letter-spacing:1px;">🅿 SmartPark</span>
                </td></tr>
                <tr><td style="padding:36px 40px;">
                  <p style="margin:0 0 12px;font-size:16px;color:#222;">Bonjour <strong>{$name}</strong>,</p>
                  <p style="margin:0 0 24px;font-size:15px;color:#444;line-height:1.6;">
                    Nous avons reçu une demande de réinitialisation de votre mot de passe. Voici votre code de vérification :
                  </p>
                  <div style="text-align:center;margin:0 0 28px;">
                    <span style="display:inline-block;background:#f0f9f4;border:2px dashed #1a7a4a;border-radius:10px;padding:18px 40px;font-size:36px;font-weight:700;letter-spacing:10px;color:#1a7a4a;">{$code}</span>
                  </div>
                  <p style="margin:0 0 8px;font-size:14px;color:#666;">Ce code est valable pendant <strong>60 minutes</strong>.</p>
                  <p style="margin:0 0 24px;font-size:14px;color:#666;">Si vous n'avez pas fait cette demande, ignorez simplement cet email — votre mot de passe ne sera pas modifié.</p>
                  <hr style="border:none;border-top:1px solid #eee;margin:0 0 20px;">
                  <p style="margin:0;font-size:13px;color:#aaa;text-align:center;">© SmartPark — Ne répondez pas à cet email.</p>
                </td></tr>
              </table>
            </td></tr>
          </table>
        </body>
        </html>
        HTML;
    }
}
