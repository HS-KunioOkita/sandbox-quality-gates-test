/** 会員割引率（10%） */
export const MEMBER_DISCOUNT_RATE = 0.1;

/** 会員割引が適用される最低金額。この金額以上のときに割引する */
export const MEMBER_DISCOUNT_MIN_PRICE = 1000;

/** 注文のステータス */
export type OrderStatus = 'PENDING' | 'PAID' | 'CANCELLED';
