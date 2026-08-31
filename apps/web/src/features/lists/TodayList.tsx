import TaskList from '@/features/lists/TaskList'

type TodayListProps = {
  csrfToken: string
}

function TodayList({ csrfToken }: TodayListProps) {
  return <TaskList csrfToken={csrfToken} view="today" />
}

export default TodayList
