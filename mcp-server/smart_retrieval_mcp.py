#!/usr/bin/env python3
"""
智能双重检索系统 - MCP集成版本
Phase 3: MCP Integration
"""

import json
import os
import logging
from typing import List, Dict, Any, Optional, Set
from datetime import datetime
import asyncio
from graphiti_core import Graphiti
from graphiti_core.edges import EntityEdge

# 配置logger
logger = logging.getLogger(__name__)


class SmartRetrievalMCP:
    """智能检索系统：MCP集成版本"""
    
    def __init__(self, graphiti_client: Optional[Graphiti] = None):
        self.graphiti_client = graphiti_client
        self.search_history = []
        self.term_associations = {}
        self.learning_enabled = True
        self.max_facts = 20
        self.max_episodes = 50
        
        # 加载已有的学习数据
        self.load_learning_data()
    
    async def search(self, 
                    query: str, 
                    group_ids: Optional[List[str]] = None,
                    learn: bool = True) -> Dict[str, Any]:
        """
        主检索方法 - Facts发现 + Episodes获取
        
        Args:
            query: 搜索查询
            group_ids: 限定的group_id列表
            learn: 是否启用学习
            
        Returns:
            包含facts、episodes和学习信息的结果字典
        """
        start_time = datetime.now()
        
        # 默认group_ids
        if not group_ids:
            group_ids = ["volunteer-job-procedures", "volunteer-job-preferences", "volunteer-job"]
        
        # Step 1: 查询扩展（使用已学习的关联）
        expanded_query = self._expand_query(query)
        
        # Step 2: Facts快速发现
        facts = await self._search_facts(expanded_query, group_ids)
        
        # Step 3: 从Facts提取Episode UUIDs
        episode_uuids = self._extract_episode_uuids(facts)
        
        # Step 4: 获取完整Episodes
        episodes = await self._fetch_episodes(episode_uuids, group_ids)
        
        # Step 5: 学习关联（如果启用）
        if learn and self.learning_enabled:
            self._learn_from_results(query, facts, episodes)
        
        # Step 6: 构建结果
        result = {
            'query': query,
            'expanded_query': expanded_query,
            'facts': facts,
            'episodes': episodes,
            'facts_count': len(facts),
            'episodes_count': len(episodes),
            'search_time': (datetime.now() - start_time).total_seconds(),
            'learned_terms': self.term_associations.get(query, [])
        }
        
        # 记录搜索历史
        self.search_history.append({
            'timestamp': datetime.now().isoformat(),
            'query': query,
            'results': result
        })
        
        return result
    
    def _expand_query(self, query: str) -> str:
        """使用学习的关联扩展查询"""
        expanded_terms = [query]
        
        # 添加直接关联的词
        if query in self.term_associations:
            expanded_terms.extend(self.term_associations[query][:5])
        
        # 检查查询中的每个词
        words = query.split()
        for word in words:
            if word in self.term_associations:
                expanded_terms.extend(self.term_associations[word][:3])
        
        # 去重并组合
        unique_terms = []
        seen = set()
        for term in expanded_terms:
            if term.lower() not in seen:
                seen.add(term.lower())
                unique_terms.append(term)
        
        return ' '.join(unique_terms)
    
    async def _search_facts(self, query: str, group_ids: List[str]) -> List[Dict]:
        """执行Facts搜索"""
        if not self.graphiti_client:
            return []
        
        try:
            # 使用Graphiti客户端搜索
            search_results = await self.graphiti_client.search(
                query=query,
                num_results=self.max_facts,
                group_ids=group_ids
            )
            
            # 格式化Facts结果
            facts = []
            for edge in search_results:
                fact_dict = {
                    'uuid': edge.uuid,
                    'fact': edge.fact,
                    'source_node_uuid': edge.source_node_uuid,
                    'target_node_uuid': edge.target_node_uuid,
                    'episodes': edge.episodes if hasattr(edge, 'episodes') else [],
                    'created_at': edge.created_at.isoformat() if edge.created_at else None
                }
                facts.append(fact_dict)
            
            return facts
        except Exception as e:
            print(f"⚠️ Error searching facts: {e}")
            return []
    
    def _extract_episode_uuids(self, facts: List[Dict]) -> List[str]:
        """从Facts中提取Episode UUIDs"""
        episode_uuids = set()
        for fact in facts:
            episodes = fact.get('episodes', [])
            if isinstance(episodes, list):
                episode_uuids.update(episodes)
        return list(episode_uuids)
    
    async def _fetch_episodes(self, uuids: List[str], group_ids: List[str]) -> List[Dict]:
        """批量获取Episodes"""
        if not self.graphiti_client or not uuids:
            return []
        
        episodes = []
        try:
            # 获取所有group的episodes
            for group_id in group_ids:
                group_episodes = await self.graphiti_client.driver.get_episodes(
                    group_id=group_id,
                    last_n=self.max_episodes
                )
                
                # 过滤出匹配UUID的episodes
                for episode in group_episodes:
                    if hasattr(episode, 'uuid') and episode.uuid in uuids:
                        episode_dict = {
                            'uuid': episode.uuid,
                            'name': episode.name if hasattr(episode, 'name') else '',
                            'content': episode.content if hasattr(episode, 'content') else '',
                            'group_id': episode.group_id if hasattr(episode, 'group_id') else '',
                            'created_at': episode.created_at.isoformat() if hasattr(episode, 'created_at') else None,
                            'source': episode.source if hasattr(episode, 'source') else 'text'
                        }
                        episodes.append(episode_dict)
                        
        except Exception as e:
            print(f"⚠️ Error fetching episodes: {e}")
        
        return episodes
    
    async def get_episode_by_uuid(self, uuid: str) -> Optional[Dict]:
        """按UUID直接查询Episode - 优化版本"""
        if not self.graphiti_client or not self.graphiti_client.driver:
            logger.error("Graphiti client or driver not initialized")
            return None
        
        try:
            # 直接使用Cypher查询，利用Neo4j索引
            query = """
            MATCH (e:Episodic {uuid: $uuid})
            RETURN
                e.uuid AS uuid,
                e.name AS name,
                e.content AS content,
                e.group_id AS group_id,
                e.created_at AS created_at,
                e.valid_at AS valid_at,
                e.source AS source,
                e.source_description AS source_description,
                e.entity_edges AS entity_edges
            LIMIT 1
            """
            
            # 执行查询
            records, _, _ = await self.graphiti_client.driver.execute_query(
                query,
                uuid=uuid,
                routing_='r'  # 只读路由
            )
            
            # 如果找到了记录
            if records and len(records) > 0:
                record = records[0]
                return {
                    'uuid': record.get('uuid'),
                    'name': record.get('name', ''),
                    'content': record.get('content', ''),
                    'group_id': record.get('group_id', ''),
                    'created_at': record.get('created_at').isoformat() if record.get('created_at') else None,
                    'valid_at': record.get('valid_at').isoformat() if record.get('valid_at') else None,
                    'source': record.get('source', 'text'),
                    'source_description': record.get('source_description', ''),
                    'entity_edges': record.get('entity_edges', [])
                }
            
            logger.debug(f"Episode with UUID {uuid} not found")
            return None
            
        except Exception as e:
            logger.error(f"Error getting episode by UUID {uuid}: {str(e)}")
            return None
    
    def _learn_from_results(self, query: str, facts: List[Dict], episodes: List[Dict]):
        """从搜索结果中学习关联"""
        learned_terms = set()
        
        # 从Facts中学习
        for fact in facts[:10]:
            fact_text = fact.get('fact', '')
            words = fact_text.split()
            for word in words:
                if len(word) > 2:
                    learned_terms.add(word.lower())
        
        # 从Episodes中学习关键词
        for episode in episodes[:5]:
            content = episode.get('content', '')
            if isinstance(content, dict):
                # 提取JSON中的keywords
                keywords = content.get('keywords', {})
                if isinstance(keywords, dict):
                    for key_type in ['chinese', 'english', 'technical']:
                        terms = keywords.get(key_type, [])
                        if isinstance(terms, list):
                            learned_terms.update([t.lower() for t in terms if isinstance(t, str)])
        
        # 更新关联记忆
        if query not in self.term_associations:
            self.term_associations[query] = []
        
        existing = set(self.term_associations[query])
        new_terms = learned_terms - existing - {query.lower()}
        
        self.term_associations[query].extend(list(new_terms)[:10])
        
        # 保存学习数据
        self.save_learning_data()
        
        print(f"🧠 Learned {len(new_terms)} new associations for '{query}'")
    
    def save_learning_data(self):
        """保存学习数据到本地文件"""
        data = {
            'term_associations': self.term_associations,
            'last_updated': datetime.now().isoformat()
        }
        
        file_path = os.path.join(
            os.path.dirname(__file__),
            'search_learning.json'
        )
        
        try:
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"⚠️ Failed to save learning data: {e}")
    
    def load_learning_data(self):
        """加载已有的学习数据"""
        file_path = os.path.join(
            os.path.dirname(__file__),
            'search_learning.json'
        )
        
        if os.path.exists(file_path):
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    self.term_associations = data.get('term_associations', {})
                    print(f"📖 Loaded {len(self.term_associations)} learned associations")
            except Exception as e:
                print(f"⚠️ Failed to load learning data: {e}")
    
    def get_search_stats(self) -> Dict[str, Any]:
        """获取搜索统计信息"""
        return {
            'total_searches': len(self.search_history),
            'learned_queries': len(self.term_associations),
            'total_associations': sum(len(v) for v in self.term_associations.values()),
            'recent_queries': [s['query'] for s in self.search_history[-5:]],
            'top_learned': sorted(
                self.term_associations.items(), 
                key=lambda x: len(x[1]), 
                reverse=True
            )[:5]
        }