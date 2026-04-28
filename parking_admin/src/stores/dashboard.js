import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { listAdminParkings } from '@/services/admin/parkingApi'
import { listAdminUsers } from '@/services/admin/userManagementApi'

const revenueByPeriod = {
  'Cette semaine': [12800, 14500, 13200, 16750, 15400, 17900, 18300],
  'Semaine derniere': [10800, 12100, 11900, 13200, 12800, 14000, 14600],
  'Ce mois-ci': [9200, 11800, 12100, 13600, 14200, 15500, 14950],
}

const asDisplayCount = (value) => Number(value ?? 0).toLocaleString('fr-FR')

export const useDashboardStore = defineStore('dashboard', () => {
  const statCards = ref([
    { title: 'Total parkings', value: '1,429', subtitle: 'Tous sites confondus', badgeLabel: '' },
    { title: 'Total utilisateurs', value: '28.5k', subtitle: 'Croissance mensuelle de 12 %', badgeLabel: '' },
    { title: 'Revenus totaux', value: '$142k', subtitle: 'Apercu des performances d octobre', badgeLabel: '' },
    {
      title: 'Vehicules actifs',
      value: '892',
      subtitle: 'Flux d occupation en temps reel',
      badgeLabel: 'Critique',
      badgeTone: 'danger',
    },
  ])

  const aiSuggestions = ref([
    {
      title: 'Reaffecter les vehicules electriques vers Harbor Pier 4',
      description: '+8 % de debit prevu pendant le pic de 7h30 a 9h00.',
    },
    {
      title: 'Activer la voie de debordement a Downtown Central',
      description: 'La demande depasse 90 % depuis trois matinees consecutives.',
    },
    {
      title: 'Lancer des incitations fidelite pour les zones sous-utilisees',
      description: 'Tech District peut absorber 120 vehicules supplementaires cet apres-midi.',
    },
  ])

  const recentActivity = ref([
    {
      id: 'evt-1',
      title: 'Downtown Central a atteint 92 % d occupation',
      timestamp: 'il y a 2 min',
      detail: 'Protocole de delestage declenche automatiquement.',
    },
    {
      id: 'evt-2',
      title: 'Paiement d abonnement traite',
      timestamp: 'il y a 11 min',
      detail: 'Le proprietaire North Gate Holdings a ete facture 2 480 $.',
    },
    {
      id: 'evt-3',
      title: 'Regle de securite mise a jour',
      timestamp: 'il y a 27 min',
      detail: 'Nouvelle plage d acces appliquee aux operateurs de nuit.',
    },
    {
      id: 'evt-4',
      title: 'Maintenance de zone terminee',
      timestamp: 'il y a 1 h',
      detail: 'La voie C de Harbor Pier est rouverte au public.',
    },
  ])

  const selectedPeriod = ref('Cette semaine')
  const statsLoading = ref(false)
  const statsError = ref('')

  const periodOptions = computed(() => Object.keys(revenueByPeriod))

  const revenueChartData = computed(() => {
    return {
      labels: ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
      datasets: [
        {
          label: 'Revenus hebdomadaires',
          data: revenueByPeriod[selectedPeriod.value],
          borderRadius: 10,
          backgroundColor: '#004ac6',
          maxBarThickness: 34,
        },
      ],
    }
  })

  const revenueChartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false,
      },
      tooltip: {
        callbacks: {
          label: (context) => `$${context.parsed.y.toLocaleString()}`,
        },
      },
    },
    scales: {
      x: {
        grid: {
          display: false,
        },
        ticks: {
          color: '#737686',
        },
      },
      y: {
        grid: {
          color: 'rgba(115, 118, 134, 0.18)',
        },
        ticks: {
          color: '#737686',
          callback: (value) => `$${Number(value).toLocaleString()}`,
        },
      },
    },
  }

  const setPeriod = (period) => {
    if (periodOptions.value.includes(period)) {
      selectedPeriod.value = period
    }
  }

  const setRealtimeTotals = ({ parkingsTotal, usersTotal }) => {
    const safeParkingsTotal = Math.max(0, Number(parkingsTotal) || 0)
    const safeUsersTotal = Math.max(0, Number(usersTotal) || 0)

    statCards.value = statCards.value.map((card, index) => {
      if (index === 0) {
        return {
          ...card,
          value: asDisplayCount(safeParkingsTotal),
          subtitle: 'Depuis la base de donnees',
        }
      }

      if (index === 1) {
        return {
          ...card,
          value: asDisplayCount(safeUsersTotal),
          subtitle: 'Depuis la base de donnees',
        }
      }

      return card
    })
  }

  const loadRealtimeTotals = async ({ authHeaders } = {}) => {
    if (typeof authHeaders !== 'function') {
      return {
        ok: false,
        message: 'Headers auth manquants.',
      }
    }

    statsLoading.value = true
    statsError.value = ''

    try {
      const [parkingsResult, usersResult] = await Promise.all([
        listAdminParkings({ authHeaders }),
        listAdminUsers({ authHeaders }),
      ])

      if (!parkingsResult.ok || !usersResult.ok) {
        const message = !parkingsResult.ok
          ? parkingsResult.message
          : usersResult.message

        statsError.value = message

        return {
          ok: false,
          message,
        }
      }

      const usersTotalFromApi = Number(usersResult.totals?.all)
      const usersTotal = Number.isFinite(usersTotalFromApi)
        ? usersTotalFromApi
        : (Array.isArray(usersResult.data) ? usersResult.data.length : 0)

      setRealtimeTotals({
        parkingsTotal: Array.isArray(parkingsResult.data) ? parkingsResult.data.length : 0,
        usersTotal,
      })

      return {
        ok: true,
      }
    } finally {
      statsLoading.value = false
    }
  }

  return {
    statCards,
    aiSuggestions,
    recentActivity,
    selectedPeriod,
    statsLoading,
    statsError,
    periodOptions,
    revenueChartData,
    revenueChartOptions,
    setPeriod,
    loadRealtimeTotals,
  }
})
