Q: eoapi-k8s uses the postgres-operator from crunchydata. Is there a reason why you have chosen this solution? There is also a postgres-operator from Zalando. What are the benefits using an operator instead of a postgres helm chart?

A: We made the choice to use Crunchydata's operator over Zalando's operator and cloudnative-pg's operator (they all install operators even if using the helm install option) after considering the following things:

1. quality of the documentation
2. backlog of issues
3. knowing that a lot of core PG contributors work at Crunchydata and hearing about some of the cutting edge things they are doing
4. talking with other folks in our community

That said, what we want out of an operator "most" of the above options share:

1. backups
2. some kind of connection pooling option set up for us
3. good solid docs and choices about how upgrades work

See also https://github.com/developmentseed/eoapi-k8s/issues/132
