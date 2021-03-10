RENEWER_RUN()
{
    SPACE_SIGNATURE=""
    SPACE_ENV="daysUntilExpire=\${daysUntilExpire:-20} certDir=\${certDir:-/mnt/certs} certsList=\${certsList:-/mnt/certs_list/certs.txt}"
    SPACE_DEP="PRINT _PERFORM"

    if [ -z "${daysUntilExpire}" ]; then
        PRINT "Missing env variable daysUntilExpire" "error" 0
        return 1
    fi

    if [ ! -d "${certDir}" ]; then
        PRINT "Cert dir does not exist: ${certDir}" "error" 0
        return 1
    fi

    if [ ! -f "${certsList}" ]; then
        PRINT "Certs list does not exist: ${certsList}" "error" 0
        return 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        PRINT "tar not installed" "error" 0
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        PRINT "curl not installed" "error" 0
        return
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        PRINT "openssl not installed" "error" 0
        return
    fi

    if ! command -v socat >/dev/null 2>&1; then
        PRINT "socat not installed" "error" 0
        return
    fi

    local secondsToLive="$((daysUntilExpire * 86400))"

    cd "${certDir}"

    _PERFORM "${certsList}" "${secondsToLive}"
}

_PERFORM()
{
    SPACE_SIGNATURE="certsList secondsToLive"
    SPACE_DEP="_GET_CERTS _CHECK_CONNECTIVITY _ISSUE_CERT PRINT _BUNDLE_CERTS"

    local certsList="${1}"
    shift

    local secondsToLive="${1}"
    shift

    local lines=
    if ! lines="$(_GET_CERTS "${certsList}" "${secondsToLive}")"; then
        return 1
    fi

    # Step through each cert, check connectivity and then issue a renewal to LE.
    local nl="
"
    local line=
    local certsIssued=0
    local domainsDone=""
    local anyFailure=0
    local issueFailure=0
    local ifs="${IFS}"
    local IFS="${nl}"
    for line in $lines; do
        IFS="${ifs}"
        local certFile="${line%%[ ]*}"
        local domains="${line#*[ ]}"
        local domain=
        local isOk=1
        PRINT "Performing connectivity probes for domains ${domains}..." "info" 0
        for domain in ${domains}; do
            if ! _CHECK_CONNECTIVITY "${domain}"; then
                isOk=0
                anyFailure=1
            fi
        done
        if [ "${isOk}" = "1" ]; then
            if _ISSUE_CERT "${certFile}" "${domains}"; then
                certsIssued="$((certsIssued+1))"
                domainsDone="${domains}${domainsDone:+ }${domainsDone}"
            else
                anyFailure=1
                issueFailure=1
            fi
        else
            PRINT "Will not renew certificate for domains: ${domains}" "error" 0
        fi
    done
    IFS="${ifs}"

    # Pack all certs into tar.gz file, if any was issued
    if [ "${certsIssued}" -gt 0 ]; then
        PRINT "${certsIssued} certs issued for domains: ${domainsDone}" "info" 0
    fi

    # We bundle cert on each invocation, regardless if any new ones were issued.
    # This to squash some logical fallacies when doing rearrangements in the certs list file.
    if ! _BUNDLE_CERTS "${certsList}"; then
        anyFailure=1
    fi

    # Always return error if any cert failed to renew, in this way this script will get rerun soon again to retry.
    if [ "${issueFailure}" = "1" ]; then
        # In this case we might have hit a rate limit.
        # Sleep some so we don't hammer the LE API with retries
        sleep 10
        return 1
    elif [ "${anyFailure}" = "1" ]; then
        # Sleep some so we don't hammer the LE API with retries
        sleep 10
        return 1
    fi
}

_BUNDLE_CERTS()
{
    SPACE_SIGNATURE="certsList"
    SPACE_DEP="PRINT _GET_CERTS"

    local certsList="${1}"
    shift

    local lines=
    if ! lines="$(_GET_CERTS "${certsList}" "0")"; then
        return 1
    fi

    local nl="
"
    local line=
    printf "%s\\n" "I used to be The Astro Chicken. Not I'm simply a placeholder for empty tar archives..." >".astrochicken"
    local files=".astrochicken"
    local ifs="${IFS}"
    local IFS="${nl}"
    for line in $lines; do
        IFS="${ifs}"
        local certFile="${line%%[ ]*}"
        if [ -f "${certFile}" ]; then
            files="${files}${files:+ }${certFile}"
        fi
    done
    IFS="${ifs}"

    if ! tar czf "certs.tar.gz.tmp" ${files}; then
        PRINT "Could not tar certs" "error" 0
        return 1
    fi
    mv -f "certs.tar.gz.tmp" "certs.tar.gz"
}

# Check what certs we should have, what we have and their ttl.
# Outputs on stdout all which should be issued.
# if secondsToLive=0 then output all certs, regardless.
_GET_CERTS()
{
    SPACE_SIGNATURE="certsList secondsToLive"
    SPACE_DEP="STRING_HASH PRINT"

    local certsList="${1}"
    shift

    local secondsToLive="${1}"
    shift

    local domains=
    local hash=
    while IFS='' read -r domains || [ -n "${domains}" ]; do
        if [ "${domains#[#]}" != "${domains}" ]; then
            continue
        fi
        STRING_HASH "${domains}" hash
        local certFile="${hash}.pem"
        local issue=1
        if [ "${secondsToLive}" -gt 0 ]; then
            if [ -f "${certFile}" ]; then
                # Check valid cert file
                if ! openssl x509 -in "${certFile}" -text -noout >/dev/null 2>&1; then
                    PRINT "Cert is invalid ${certFile}" "error" 0
                fi
                # Check valid date
                if openssl x509 -checkend "${secondsToLive}" -noout -in "${certFile}" >/dev/null; then
                    issue=0
                else
                    PRINT "Cert ${certFile} ($domains) has/is expiring" "info" 0
                fi
            fi
        fi
        if [ "${issue}" = "1" ]; then
            printf "%s %s\\n" "${certFile}" "${domains}"
        fi
    done <"${certsList}"
}

# For all to be issued, check that the DNS connectivity is working for each domain.
# There is a chance the whole process can stall if a single DNS entry does not work.
_CHECK_CONNECTIVITY()
{
    local domain="${1}"
    shift

    local randomID="$(awk 'BEGIN{min=1;max=65535;srand(); print int(min+rand()*(max-min+1))}')"

    # Create listener which will spawn a process and return the random ID we have.
    socat TCP-LISTEN:8080,reuseaddr,fork exec:'sh -c "\"printf \\\"HTTP/1.1 200 OK\\\r\\\nContent-Length: '${#randomID}'\\\r\\\n\\\r\\\n'${randomID}'\\\"\""' &
    pid="$!"

    local content=
    content="$(curl -Ls "http://${domain}/.well-known/acme-challenge/probe")"

    kill "${pid}"

    if [ "${content}" = "${randomID}" ]; then
        return 0
    fi

    PRINT "Domain ${domain} does not connect to here. DNS malconfiguration? Skipping this cert" "error" 0
    return 1
}

# Use Letsencrypt to issue certs and save them.
# Create the tar.gz bundle when done.
_ISSUE_CERT()
{
    SPACE_SIGNATURE="certFile domains"
    SPACE_DEP="PRINT"

    local certFile="${1}"
    shift

    local domains="${1}"
    shift

    PRINT "Update cert for domains: ${domains}" "info" 0

    local domains2=
    local domain=
    for domain in ${domains}; do
        domains2="${domains2} -d ${domain}"
    done

    if ! /acme.sh --issue --cert-home . --standalone ${domains2} --httpport 8080 --fullchain-file "${certFile}.tmp" --key-file "${certFile}.key" --force >/dev/null; then
        PRINT "Could not issue cert." "error" 0
        return 1
    fi

    cat "${certFile}.key" >> "${certFile}.tmp"
    rm "${certFile}.key"
    mv -f "${certFile}.tmp" "${certFile}"
    PRINT "Cert issued for ${domains}" "ok" 0
}
