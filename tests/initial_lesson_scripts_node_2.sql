SELECT * FROM aak_cluster_example.events;


-- INSERT INTO CLUSTER TABLE (2 NODE)
INSERT INTO aak_cluster_example.events (id, event_type, payload) VALUES
    (6, 'signup',   'user=charlie'),
    (7, 'click',    'page=pricing'),
    (8, 'purchase', 'item=gadget');


SELECT * FROM aak_cluster_example.events;


INSERT INTO aak_cluster_example.events_distributed (id, event_type, payload) VALUES
    (9,  'click',  'page=about'),
    (10, 'logout', 'user=bob');


SELECT * FROM aak_noncluster_example.events_local;