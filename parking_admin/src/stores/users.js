import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { listAdminGlobalHistory, listAdminUsers, updateAdminOwnerStatus } from '@/services/admin/userManagementApi'

const roleTabs = [
  { key: 'ALL', label: 'Tous les roles' },
  { key: 'ADMIN', label: 'Administrateurs' },
  { key: 'OWNER', label: 'Proprietaires de parking' },
  { key: 'CLIENT', label: 'Clients' },
]

const normalizeEmail = (value) => {
  return String(value ?? '').trim().toLowerCase()
}

const normalizeRoleKey = (value) => {
  const role = String(value ?? '').trim().toUpperCase()
  return ['ADMIN', 'OWNER', 'CLIENT'].includes(role) ? role : 'CLIENT'
}

const toRoleLabel = (roleKey, fallback = '') => {
  if (fallback) {
    return fallback
  }

  if (roleKey === 'ADMIN') {
    return 'Administrateur'
  }

  if (roleKey === 'OWNER') {
    return 'Proprietaire de parking'
  }

  return 'Client'
}

const normalizeAccountStatus = (value) => {
  return String(value ?? '').trim().toLowerCase() === 'blocked' ? 'blocked' : 'active'
}

const formatRelativeTime = (value) => {
  if (!value) {
    return 'Jamais'
  }

  const timestamp = new Date(String(value)).getTime()
  if (Number.isNaN(timestamp)) {
    return 'Date invalide'
  }

  const diffMs = Date.now() - timestamp
  const future = diffMs < 0
  const deltaMs = Math.abs(diffMs)
  const minuteMs = 60 * 1000
  const hourMs = 60 * minuteMs
  const dayMs = 24 * hourMs

  if (deltaMs < minuteMs) {
    return future ? 'dans quelques secondes' : 'a l instant'
  }

  if (deltaMs < hourMs) {
    const minutes = Math.round(deltaMs / minuteMs)
    return future ? `dans ${minutes} min` : `il y a ${minutes} min`
  }

  if (deltaMs < dayMs) {
    const hours = Math.round(deltaMs / hourMs)
    return future ? `dans ${hours} h` : `il y a ${hours} h`
  }

  const days = Math.round(deltaMs / dayMs)
  return future ? `dans ${days} j` : `il y a ${days} j`
}

const formatDateTime = (value) => {
  if (!value) {
    return '-'
  }

  const date = new Date(String(value))

  if (Number.isNaN(date.getTime())) {
    return '-'
  }

  return date.toLocaleString('fr-FR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

const asDisplayCount = (value) => {
  return Number(value ?? 0).toLocaleString('fr-FR')
}

const asStatusView = ({ roleKey, accountStatus, statusLabel, statusTone }) => {
  if (roleKey === 'OWNER') {
    return {
      status: accountStatus === 'blocked' ? 'Suspendu' : 'Actif',
      statusTone: accountStatus === 'blocked' ? 'danger' : 'success',
    }
  }

  return {
    status: String(statusLabel ?? '').trim() || 'Actif',
    statusTone: String(statusTone ?? '').trim() || 'success',
  }
}

const normalizeUserRow = (item = {}) => {
  const roleKey = normalizeRoleKey(item.roleKey)
  const accountStatus = normalizeAccountStatus(item.accountStatus)
  const actorId = String(item.id ?? '').trim()
  const role = toRoleLabel(roleKey, String(item.roleLabel ?? '').trim())
  const statusView = asStatusView({
    roleKey,
    accountStatus,
    statusLabel: item.statusLabel,
    statusTone: item.statusTone,
  })
  const lastActiveAt = String(item.lastActiveAt ?? '').trim()

  return {
    id: actorId ? `${roleKey}-${actorId}` : `${roleKey}-unknown-${Date.now()}`,
    actorId,
    name: String(item.name ?? '').trim() || 'Utilisateur',
    email: normalizeEmail(item.email),
    phone: String(item.phone ?? '').trim(),
    role,
    roleKey,
    lastActiveAt,
    lastActive: formatRelativeTime(lastActiveAt),
    ip: '-',
    status: statusView.status,
    statusTone: statusView.statusTone,
    accountStatus,
    subscriptionStatus: String(item.subscriptionStatus ?? 'active').trim().toLowerCase() || 'active',
    createdAt: String(item.createdAt ?? '').trim(),
    updatedAt: String(item.updatedAt ?? '').trim(),
  }
}

const normalizeHistoryEvent = (item = {}, index = 0) => {
  const occurredAt = String(item.occurredAt ?? '').trim()

  return {
    id: String(item.eventId ?? '').trim() || `event-${Date.now()}-${index}`,
    category: String(item.category ?? '').trim() || 'Systeme',
    categoryTone: String(item.categoryTone ?? '').trim() || 'neutral',
    action: String(item.action ?? '').trim() || 'Mise a jour',
    details: String(item.details ?? '').trim() || '-',
    actor: String(item.actor ?? '').trim() || '-',
    occurredAt,
    occurredAtLabel: formatDateTime(occurredAt),
  }
}

export const useUsersStore = defineStore('users', () => {
  const tabs = ref(roleTabs)
  const activeTab = ref('ALL')
  const users = ref([])
  const globalHistory = ref([])
  const usersLoading = ref(false)
  const historyLoading = ref(false)
  const usersError = ref('')
  const historyError = ref('')
  const actionError = ref('')
  const actionSuccess = ref('')
  const ownerStatusUpdateMap = ref({})
  const nextLocalOwnerId = ref(1)

  const stats = computed(() => {
    const totalUsers = users.value.length
    const owners = users.value.filter((user) => user.roleKey === 'OWNER').length
    const clients = users.value.filter((user) => user.roleKey === 'CLIENT').length
    const ownersActive = users.value.filter((user) => user.roleKey === 'OWNER' && user.accountStatus !== 'blocked').length
    const ownersBlocked = users.value.filter((user) => user.roleKey === 'OWNER' && user.accountStatus === 'blocked').length

    return [
      { title: 'Total utilisateurs', value: asDisplayCount(totalUsers), subtitle: 'Tous roles confondus' },
      { title: 'Owners actifs', value: asDisplayCount(ownersActive), subtitle: `${asDisplayCount(owners)} proprietaires au total` },
      { title: 'Owners suspendus', value: asDisplayCount(ownersBlocked), subtitle: 'Activation selon abonnement' },
      { title: 'Clients', value: asDisplayCount(clients), subtitle: 'Comptes clients inscrits' },
    ]
  })

  const filteredUsers = computed(() => {
    if (activeTab.value === 'ALL') {
      return users.value
    }

    return users.value.filter((user) => user.roleKey === activeTab.value)
  })

  const historyEvents = computed(() => globalHistory.value)

  const setActiveTab = (tab) => {
    const exists = tabs.value.some((item) => item.key === tab)

    if (exists) {
      activeTab.value = tab
    }
  }

  const hasUserEmail = (email) => {
    const normalized = normalizeEmail(email)

    if (!normalized) {
      return false
    }

    return users.value.some((user) => normalizeEmail(user.email) === normalized)
  }

  const addOwnerAccount = ({ name, email, phone, parkingName, parkingId, ownerId, accountStatus, subscriptionStatus } = {}) => {
    const safeName = String(name ?? '').trim()
    const normalizedEmail = normalizeEmail(email)

    if (!safeName || !normalizedEmail) {
      return {
        ok: false,
        message: 'Nom et email owner obligatoires.',
      }
    }

    if (hasUserEmail(normalizedEmail)) {
      return {
        ok: false,
        message: 'Cet email owner existe deja.',
      }
    }

    const safeOwnerId = String(ownerId ?? '').trim()
    const actorId = safeOwnerId || `local-owner-${nextLocalOwnerId.value}`
    if (!safeOwnerId) {
      nextLocalOwnerId.value += 1
    }

    const normalizedAccountStatus = normalizeAccountStatus(accountStatus)
    const normalizedSubscriptionStatus = String(subscriptionStatus ?? 'active').trim().toLowerCase() || 'active'

    const parkingMeta = [
      parkingName ? `Parking: ${parkingName}` : '',
      parkingId ? `ID: ${parkingId}` : '',
      phone ? `Tel: ${String(phone).trim()}` : '',
    ]
      .filter(Boolean)
      .join(' | ')

    const user = {
      id: `OWNER-${actorId}`,
      actorId,
      name: safeName,
      email: normalizedEmail,
      phone: String(phone ?? '').trim(),
      role: 'Proprietaire de parking',
      roleKey: 'OWNER',
      lastActiveAt: new Date().toISOString(),
      lastActive: 'a l instant',
      ip: parkingMeta || '-',
      status: normalizedAccountStatus === 'blocked' ? 'Suspendu' : 'Actif',
      statusTone: normalizedAccountStatus === 'blocked' ? 'danger' : 'success',
      accountStatus: normalizedAccountStatus,
      subscriptionStatus: normalizedSubscriptionStatus,
      createdAt: '',
      updatedAt: '',
    }

    users.value.unshift(user)

    return {
      ok: true,
      user,
    }
  }

  const removeUserByEmail = (email) => {
    const normalized = normalizeEmail(email)

    if (!normalized) {
      return false
    }

    const before = users.value.length
    users.value = users.value.filter((user) => normalizeEmail(user.email) !== normalized)

    return users.value.length !== before
  }

  const applyUsersFromApi = (items) => {
    users.value = Array.isArray(items) ? items.map((item) => normalizeUserRow(item)) : []
  }

  const applyHistoryFromApi = (events) => {
    globalHistory.value = Array.isArray(events)
      ? events.map((event, index) => normalizeHistoryEvent(event, index))
      : []
  }

  const loadUsers = async ({ authHeaders } = {}) => {
    if (typeof authHeaders !== 'function') {
      return {
        ok: false,
        message: 'Headers auth manquants.',
      }
    }

    usersLoading.value = true
    usersError.value = ''

    try {
      const result = await listAdminUsers({ authHeaders })

      if (!result.ok) {
        usersError.value = result.message
        return result
      }

      applyUsersFromApi(result.data)
      return {
        ok: true,
      }
    } finally {
      usersLoading.value = false
    }
  }

  const loadGlobalHistory = async ({ authHeaders, limit = 120 } = {}) => {
    if (typeof authHeaders !== 'function') {
      return {
        ok: false,
        message: 'Headers auth manquants.',
      }
    }

    historyLoading.value = true
    historyError.value = ''

    try {
      const result = await listAdminGlobalHistory({ authHeaders, limit })

      if (!result.ok) {
        historyError.value = result.message
        return result
      }

      applyHistoryFromApi(result.data)
      return {
        ok: true,
      }
    } finally {
      historyLoading.value = false
    }
  }

  const refreshData = async ({ authHeaders, historyLimit = 120 } = {}) => {
    const [usersResult, historyResult] = await Promise.all([
      loadUsers({ authHeaders }),
      loadGlobalHistory({ authHeaders, limit: historyLimit }),
    ])

    return {
      ok: Boolean(usersResult.ok && historyResult.ok),
      users: usersResult,
      history: historyResult,
    }
  }

  const isUpdatingOwnerStatus = (userId) => {
    return Boolean(ownerStatusUpdateMap.value[String(userId ?? '')])
  }

  const toggleOwnerStatus = async ({ user, authHeaders } = {}) => {
    if (!user || user.roleKey !== 'OWNER') {
      return {
        ok: false,
        message: 'Action reservee aux owners.',
      }
    }

    if (typeof authHeaders !== 'function') {
      return {
        ok: false,
        message: 'Headers auth manquants.',
      }
    }

    const userKey = String(user.id ?? '')
    const ownerId = String(user.actorId ?? '')
    if (!ownerId) {
      return {
        ok: false,
        message: 'Identifiant owner manquant.',
      }
    }

    actionError.value = ''
    actionSuccess.value = ''
    ownerStatusUpdateMap.value = {
      ...ownerStatusUpdateMap.value,
      [userKey]: true,
    }

    const nextStatus = user.accountStatus === 'blocked' ? 'active' : 'blocked'
    const subscriptionStatus = nextStatus === 'blocked' ? 'expired' : 'active'
    const reason = nextStatus === 'blocked' ? 'Abonnement owner inactif' : 'Abonnement owner active'

    try {
      const result = await updateAdminOwnerStatus({
        ownerId,
        authHeaders,
        payload: {
          accountStatus: nextStatus,
          subscriptionStatus,
          reason,
        },
      })

      if (!result.ok) {
        actionError.value = result.message
        return result
      }

      const nextOwner = normalizeUserRow(result.data ?? {})
      users.value = users.value.map((current) => {
        if (current.id !== userKey) {
          return current
        }

        return {
          ...current,
          ...nextOwner,
          id: userKey,
        }
      })

      actionSuccess.value = nextStatus === 'blocked'
        ? `Owner ${currentUserName(user)} suspendu.`
        : `Owner ${currentUserName(user)} active.`

      await loadGlobalHistory({ authHeaders })

      return {
        ok: true,
      }
    } finally {
      ownerStatusUpdateMap.value = {
        ...ownerStatusUpdateMap.value,
        [userKey]: false,
      }
    }
  }

  const currentUserName = (user) => {
    return String(user?.name ?? user?.email ?? 'owner')
  }

  return {
    stats,
    tabs,
    activeTab,
    filteredUsers,
    historyEvents,
    usersLoading,
    historyLoading,
    usersError,
    historyError,
    actionError,
    actionSuccess,
    setActiveTab,
    hasUserEmail,
    addOwnerAccount,
    removeUserByEmail,
    loadUsers,
    loadGlobalHistory,
    refreshData,
    toggleOwnerStatus,
    isUpdatingOwnerStatus,
  }
})
