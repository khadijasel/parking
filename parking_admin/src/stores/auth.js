import { computed, ref } from 'vue'
import { defineStore } from 'pinia'

const AUTH_STORAGE_KEY = 'parking_admin_auth_session'
const validRoles = ['admin', 'owner']

const apiBaseUrl = String(import.meta.env.VITE_API_BASE_URL ?? '/api').replace(/\/+$/, '')

const safeReadLocalStorage = (key) => {
  if (typeof window === 'undefined') {
    return null
  }

  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

const safeWriteLocalStorage = (key, value) => {
  if (typeof window === 'undefined') {
    return
  }

  try {
    window.localStorage.setItem(key, value)
  } catch {
    // Ignore local storage write issues.
  }
}

const safeRemoveLocalStorage = (key) => {
  if (typeof window === 'undefined') {
    return
  }

  try {
    window.localStorage.removeItem(key)
  } catch {
    // Ignore local storage remove issues.
  }
}

const normalizeRole = (value) => {
  const role = String(value ?? '').trim().toLowerCase()

  if (!validRoles.includes(role)) {
    return ''
  }

  return role
}

const normalizeEmail = (value) => {
  return String(value ?? '').trim().toLowerCase()
}

const toApiUrl = (path) => {
  const safePath = String(path ?? '').replace(/^\/+/, '')
  return `${apiBaseUrl}/${safePath}`
}

const parseResponseBody = async (response) => {
  const text = await response.text()

  if (!text) {
    return null
  }

  try {
    return JSON.parse(text)
  } catch {
    return { message: text }
  }
}

const firstErrorMessage = (errors) => {
  if (!errors || typeof errors !== 'object') {
    return ''
  }

  const values = Object.values(errors)

  for (const value of values) {
    if (Array.isArray(value) && value.length) {
      return String(value[0])
    }

    if (typeof value === 'string' && value) {
      return value
    }
  }

  return ''
}

const isLikelyHtml = (value) => {
  const text = String(value ?? '').trim().toLowerCase()

  if (!text) {
    return false
  }

  return text.startsWith('<!doctype html') || text.startsWith('<html') || text.includes('<body')
}

const extractApiErrorMessage = (payload, fallback = 'Operation echouee.') => {
  const message = String(payload?.message ?? '').trim()
  if (message && !isLikelyHtml(message)) {
    return message
  }

  const fieldError = firstErrorMessage(payload?.errors)
  if (fieldError && !isLikelyHtml(fieldError)) {
    return fieldError
  }

  return fallback
}

const toStoredSession = (input = {}) => {
  const role = normalizeRole(input.role)
  const email = normalizeEmail(input.email)
  const token = String(input.token ?? '').trim()

  if (!role || !email || !token) {
    return null
  }

  return {
    role,
    email,
    displayName: String(input.displayName ?? '').trim() || (role === 'admin' ? 'Administrateur' : 'Proprietaire parking'),
    token,
    tokenType: String(input.tokenType ?? 'Bearer').trim() || 'Bearer',
    actor: input.actor && typeof input.actor === 'object' ? input.actor : null,
    lastLoginAt: String(input.lastLoginAt ?? new Date().toISOString()),
  }
}

export const homePathForRole = (role) => {
  if (normalizeRole(role) === 'owner') {
    return '/owner/my-parking'
  }

  return '/dashboard'
}

export const loginPathForRole = (role) => {
  if (normalizeRole(role) === 'owner') {
    return '/auth/owner'
  }

  return '/auth/admin'
}

export const readStoredSession = () => {
  const raw = safeReadLocalStorage(AUTH_STORAGE_KEY)

  if (!raw) {
    return null
  }

  try {
    const parsed = JSON.parse(raw)
    return toStoredSession(parsed)
  } catch {
    return null
  }
}

const writeSession = (session) => {
  safeWriteLocalStorage(AUTH_STORAGE_KEY, JSON.stringify(session))
}

export const useAuthStore = defineStore('auth', () => {
  const role = ref('')
  const email = ref('')
  const displayName = ref('')
  const token = ref('')
  const tokenType = ref('Bearer')
  const actor = ref(null)
  const lastLoginAt = ref('')

  const clearSessionState = () => {
    role.value = ''
    email.value = ''
    displayName.value = ''
    token.value = ''
    tokenType.value = 'Bearer'
    actor.value = null
    lastLoginAt.value = ''
  }

  const hydrate = () => {
    const stored = readStoredSession()

    if (!stored) {
      clearSessionState()
      return
    }

    role.value = stored.role
    email.value = stored.email
    displayName.value = stored.displayName
    token.value = stored.token
    tokenType.value = stored.tokenType
    actor.value = stored.actor
    lastLoginAt.value = stored.lastLoginAt
  }

  const isAuthenticated = computed(() => {
    return Boolean(role.value && token.value)
  })

  const authHeaders = (headers = {}) => {
    const merged = { ...headers }

    if (token.value) {
      merged.Authorization = `${tokenType.value || 'Bearer'} ${token.value}`
    }

    return merged
  }

  const hasAccount = () => {
    // Local duplicate checks are no longer authoritative with backend auth.
    return false
  }

  const login = async ({ role: nextRole, email: nextEmail, password: nextPassword }) => {
    const normalizedRole = normalizeRole(nextRole)

    if (!normalizedRole) {
      return {
        ok: false,
        message: 'Role invalide.',
      }
    }

    const safeEmail = normalizeEmail(nextEmail)
    const safePassword = String(nextPassword ?? '')

    if (!safeEmail || !safePassword) {
      return {
        ok: false,
        message: 'Email et mot de passe obligatoires.',
      }
    }

    try {
      const response = await fetch(toApiUrl(`${normalizedRole}/auth/login`), {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          email: safeEmail,
          password: safePassword,
        }),
      })

      const payload = await parseResponseBody(response)

      if (!response.ok) {
        return {
          ok: false,
          message: extractApiErrorMessage(payload, 'Connexion impossible.'),
        }
      }

      const data = payload?.data ?? {}
      const actorData = normalizedRole === 'admin' ? data.admin : data.owner
      const session = toStoredSession({
        role: normalizedRole,
        email: actorData?.email ?? safeEmail,
        displayName: actorData?.name,
        token: data.token,
        tokenType: data.token_type,
        actor: actorData,
        lastLoginAt: new Date().toISOString(),
      })

      if (!session) {
        return {
          ok: false,
          message: 'Reponse backend invalide (token manquant).',
        }
      }

      role.value = session.role
      email.value = session.email
      displayName.value = session.displayName
      token.value = session.token
      tokenType.value = session.tokenType
      actor.value = session.actor
      lastLoginAt.value = session.lastLoginAt

      writeSession(session)

      return {
        ok: true,
        session,
      }
    } catch (error) {
      return {
        ok: false,
        message: `Connexion echouee: ${String(error?.message ?? error)}`,
      }
    }
  }

  const registerOwnerAccount = async ({ name, email: nextEmail, phone, password } = {}) => {
    if (role.value !== 'admin' || !token.value) {
      return {
        ok: false,
        message: 'Session admin requise pour creer un owner.',
      }
    }

    const safeName = String(name ?? '').trim()
    const safeEmail = normalizeEmail(nextEmail)
    const safePhone = String(phone ?? '').trim()
    const safePassword = String(password ?? '').trim()

    if (!safeName || !safeEmail || !safePhone || !safePassword) {
      return {
        ok: false,
        message: 'Nom, email, telephone et mot de passe owner obligatoires.',
      }
    }

    try {
      const response = await fetch(toApiUrl('admin/auth/owners'), {
        method: 'POST',
        headers: authHeaders({
          Accept: 'application/json',
          'Content-Type': 'application/json',
        }),
        body: JSON.stringify({
          name: safeName,
          email: safeEmail,
          phone: safePhone,
          password: safePassword,
          password_confirmation: safePassword,
        }),
      })

      const payload = await parseResponseBody(response)

      if (!response.ok) {
        return {
          ok: false,
          message: extractApiErrorMessage(payload, 'Creation du compte owner impossible.'),
        }
      }

      return {
        ok: true,
        owner: payload?.data ?? null,
      }
    } catch (error) {
      return {
        ok: false,
        message: `Creation du compte owner echouee: ${String(error?.message ?? error)}`,
      }
    }
  }

  const logout = async () => {
    const currentRole = role.value
    const hasToken = Boolean(token.value)

    if (currentRole && hasToken) {
      try {
        await fetch(toApiUrl(`${currentRole}/auth/logout`), {
          method: 'POST',
          headers: authHeaders({
            Accept: 'application/json',
            'Content-Type': 'application/json',
          }),
        })
      } catch {
        // Ignore network/logout failures and clear local session anyway.
      }
    }

    clearSessionState()
    safeRemoveLocalStorage(AUTH_STORAGE_KEY)

    return {
      ok: true,
    }
  }

  hydrate()

  return {
    role,
    email,
    displayName,
    token,
    tokenType,
    actor,
    lastLoginAt,
    isAuthenticated,
    hydrate,
    authHeaders,
    hasAccount,
    login,
    registerOwnerAccount,
    logout,
  }
})
