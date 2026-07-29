import { useState, type JSX } from 'react';
import { OrderList } from './features/orders/OrderList';

export function App(): JSX.Element {
  const [userId, setUserId] = useState('');

  return (
    <main>
      <h1>注文一覧</h1>
      <label>
        ユーザー ID
        <input
          value={userId}
          onChange={(event) => {
            setUserId(event.target.value);
          }}
        />
      </label>
      {userId === '' ? <p>ユーザー ID を入力してください</p> : <OrderList userId={userId} />}
    </main>
  );
}
