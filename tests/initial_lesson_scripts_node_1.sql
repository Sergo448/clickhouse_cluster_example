-- CLUSTER DATABASE
CREATE DATABASE IF NOT EXISTS aak_cluster_example ON CLUSTER company_cluster;

-- NON CLUSTER DATABASE
CREATE DATABASE IF NOT EXISTS aak_noncluster_example ON CLUSTER company_cluster;

-- CLUSTER TABLES
CREATE TABLE IF NOT EXISTS aak_cluster_example.events ON CLUSTER company_cluster
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = ReplicatedMergeTree(
	'/clickhouse/tables/{shard}/aak_cluster_example/events', 
	'{replica}'
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time, id);

CREATE TABLE IF NOT EXISTS aak_cluster_example.events_distributed ON CLUSTER company_cluster
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = Distributed(
	'company_cluster', 
	'aak_cluster_example', 
	'events', 
	rand()
);

-- NON CLUSTER TABLE
CREATE TABLE IF NOT EXISTS aak_noncluster_example.events_local
(
    id          UInt64,
    event_time  DateTime DEFAULT now(),
    event_type  String,
    payload     String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time, id);





-- INSERT INTO CLUSTER TABLE (1 NODE)
INSERT INTO aak_cluster_example.events (id, event_type, payload) VALUES
    (1, 'login',    'user=alice'),
    (2, 'click',    'page=home'),
    (3, 'purchase', 'item=widget'),
    (4, 'logout',   'user=alice'),
    (5, 'login',    'user=bob');

SELECT * FROM aak_cluster_example.events;

-- INSERT INTO CLUSTER TABLE (2 NODE)
--INSERT INTO test_replication.events (id, event_type, payload) VALUES
--    (6, 'signup',   'user=charlie'),
--    (7, 'click',    'page=pricing'),
--    (8, 'purchase', 'item=gadget');


INSERT INTO aak_noncluster_example.events_local (id, event_type, payload) VALUES
    (100, 'local_event', 'only_on_node1_a'),
    (101, 'local_event', 'only_on_node1_b'),
    (102, 'local_event', 'only_on_node1_c');

SELECT * FROM aak_noncluster_example.events_local;