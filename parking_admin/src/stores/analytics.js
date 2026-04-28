import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

const revenueData = [
  3600, 3900, 4100, 4320, 4500, 4680, 4820, 5200, 5480, 5340, 5520, 5710, 5980, 6100, 6240,
  6410, 6590, 6730, 6920, 7050, 7210, 7340, 7480, 7620, 7810, 7950, 8080, 8260, 8390, 8520,
  8710,
]

const zoneOccupancy = [
  {
    name: 'Centre-ville Central',
    value: 92,
    statusLabel: 'Eleve',
    tone: 'danger',
    badgeTone: 'danger',
  },
  {
    name: 'Quai Harbor 4',
    value: 64,
    statusLabel: 'Optimal',
    tone: 'info',
    badgeTone: 'info',
  },
  {
    name: 'Quartier Tech',
    value: 41,
    statusLabel: 'Faible',
    tone: 'neutral',
    badgeTone: 'neutral',
  },
]

const transactionsSeed = [
  ['TX-4021', 'Tesla Model 3', 'BE-4587-TR', 'Centre-ville Central', '02h 14m', 24.5, 'TERMINE'],
  ['TX-4022', 'Renault Clio', 'MA-1932-KP', 'Quai Harbor 4', '00h 42m', 8.75, 'ACTIF'],
  ['TX-4023', 'Volkswagen ID.4', 'WA-8821-ZQ', 'Quartier Tech', '03h 08m', 19.2, 'EN ATTENTE'],
  ['TX-4024', 'Hyundai Kona', 'RA-5109-DV', 'Centre-ville Central', '01h 26m', 14.3, 'TERMINE'],
  ['TX-4025', 'Peugeot 208', 'TA-2218-NL', 'Quai Harbor 4', '00h 55m', 9.1, 'ACTIF'],
  ['TX-4026', 'BMW iX1', 'CE-9833-LH', 'Centre-ville Central', '04h 05m', 37.4, 'TERMINE'],
  ['TX-4027', 'Fiat 500', 'QA-6102-BC', 'Quartier Tech', '00h 31m', 6.2, 'EN ATTENTE'],
  ['TX-4028', 'Kia Niro', 'ZE-7744-RT', 'Quai Harbor 4', '02h 02m', 17.8, 'TERMINE'],
  ['TX-4029', 'Toyota Yaris', 'PA-4503-VN', 'Centre-ville Central', '01h 10m', 11.6, 'ACTIF'],
  ['TX-4030', 'Cupra Born', 'KE-9920-MT', 'Quartier Tech', '02h 49m', 21.3, 'TERMINE'],
  ['TX-4031', 'Nissan Leaf', 'LA-6841-WS', 'Centre-ville Central', '03h 27m', 29.9, 'TERMINE'],
  ['TX-4032', 'Audi Q4 e-tron', 'SA-3092-YR', 'Quai Harbor 4', '01h 48m', 15.7, 'EN ATTENTE'],
]

const statusToneMap = {
  TERMINE: 'success',
  ACTIF: 'info',
  'EN ATTENTE': 'warning',
}

const toTransaction = (record) => {
  const [id, vehicle, plate, location, duration, amount, status] = record
  return {
    id,
    vehicle,
    plate,
    location,
    duration,
    amount,
    amountDisplay: amount.toFixed(2),
    status,
    tone: statusToneMap[status] ?? 'neutral',
  }
}

export const useAnalyticsStore = defineStore('analytics', () => {
  const revenueLabels = ref(Array.from({ length: 31 }, (_, index) => `${index + 1} oct.`))
  const transactions = ref(transactionsSeed.map(toTransaction))
  const query = ref('')
  const currentPage = ref(1)
  const pageSize = ref(6)

  const filteredTransactions = computed(() => {
    const normalizedQuery = query.value.trim().toLowerCase()

    if (!normalizedQuery) {
      return transactions.value
    }

    return transactions.value.filter((transaction) => {
      const searchable = [
        transaction.id,
        transaction.vehicle,
        transaction.plate,
        transaction.location,
        transaction.status,
      ]
        .join(' ')
        .toLowerCase()

      return searchable.includes(normalizedQuery)
    })
  })

  const totalPages = computed(() => {
    const pages = Math.ceil(filteredTransactions.value.length / pageSize.value)
    return pages > 0 ? pages : 1
  })

  const paginatedTransactions = computed(() => {
    const start = (currentPage.value - 1) * pageSize.value
    const end = start + pageSize.value

    return filteredTransactions.value.slice(start, end)
  })

  const revenueChartData = computed(() => {
    return {
      labels: revenueLabels.value,
      datasets: [
        {
          label: 'Tendances des revenus',
          data: revenueData,
          backgroundColor: '#004ac6',
          borderRadius: 8,
          maxBarThickness: 18,
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
          maxRotation: 0,
          autoSkip: true,
          maxTicksLimit: 8,
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

  const setQuery = (value) => {
    query.value = value
    currentPage.value = 1
  }

  const setPage = (page) => {
    if (page < 1 || page > totalPages.value) {
      return
    }

    currentPage.value = page
  }

  const exportRows = computed(() => {
    const headers = ['ID', 'Vehicule', 'Plaque', 'Emplacement', 'Duree', 'Montant', 'Statut']

    const rows = filteredTransactions.value.map((item) => [
      item.id,
      item.vehicle,
      item.plate,
      item.location,
      item.duration,
      item.amountDisplay,
      item.status,
    ])

    return [headers, ...rows]
  })

  return {
    query,
    currentPage,
    totalPages,
    zoneOccupancy,
    revenueChartData,
    revenueChartOptions,
    paginatedTransactions,
    filteredTransactions,
    exportRows,
    setQuery,
    setPage,
  }
})
