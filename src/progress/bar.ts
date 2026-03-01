export function calculateProgress(operation: string): number {
  const op = operation.toLowerCase();
  // 根据关键词估算进度
  if (op.includes('reading') || op.includes('读取')) return 20;
  if (op.includes('analyzing') || op.includes('分析')) return 40;
  if (op.includes('searching') || op.includes('搜索')) return 50;
  if (op.includes('generating') || op.includes('生成')) return 70;
  if (op.includes('sending') || op.includes('发送')) return 90;
  return 50; // 默认
}

export function formatProgressBar(operation: string, percentage?: number): string {
  // 如果没有百分比，自动计算
  const percent = percentage !== undefined ? percentage : calculateProgress(operation);
  
  // 生成进度条
  const filled = Math.floor(percent / 10);
  const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);
  
  // 截断操作描述
  const desc = operation.length > 50 
    ? operation.slice(0, 47) + '...' 
    : operation;
  
  return `🔄 处理中 [${bar}] ${percent}% - ${desc}`;
}
