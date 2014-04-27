module GitHub

import Main, ..Git, ..Dir

const AUTH_DATA = {
    "scopes" => ["repo"],
    "note" => "Julia Package Manager",
    "note_url" => "http://docs.julialang.org/en/latest/manual/packages/",
}

function github422(status, content)
    parsed = json().parse(content)
    err = parsed["errors"][1]
    return """
    $status: $(parsed["message"]) -- $(get(parsed, "documentation_url", ""))
       resource:   $(err["resource"])
       field:      $(err["field"])
       error code: $(err["code"])
    """
end

function user()
    if !success(`git config --global github.user`)
        error("""
        no GitHub user name configured; please configure it with:

            git config --global github.user USERNAME

        where USERNAME is replaced with your GitHub user name.
        """)
    end
    readchomp(`git config --global github.user`)
end

function json()
    isdefined(:JSON) || try require("JSON")
    catch err
        warn(err)
        error("using the GitHub API requires having the JSON package installed ")
    end
    Main.JSON
end

function curl(url::String, opts::Cmd=``)
    success(`curl --version`) || error("using the GitHub API requires having `curl` installed")
    out, proc = open(`curl -i -s -S $opts $url`,"r")
    head = readline(out)
    status = int(split(head,r"\s+";limit=3)[2])
    header = (String=>String)[]
    for line in eachline(out)
        if !ismatch(r"^\s*$",line)
            (k,v) = split(line, r":\s*", 2)
            header[k] = v
            continue
        end
        wait(proc); return status, header, readall(out)
    end
    error("strangely formatted HTTP response")
end
curl(url::String, data::Nothing, opts::Cmd=``) = curl(url,opts)
curl(url::String, data, opts::Cmd=``) =
    curl(url,`--data $(sprint(io->json().print(io,data))) $opts`)

function token(user::String=user())
    tokfile = Dir.path(".github","token")
    isfile(tokfile) && return strip(readchomp(tokfile))
    status, header, content = curl("https://api.github.com/authorizations",AUTH_DATA,`-u $user`)
    if status == 401 && get(header, "X-GitHub-OTP", "") |> x->beginswith(x, "required") && isinteractive()
        info("Two-factor authentication in use.  Enter auth code.  (You may need to re-enter your password.)")
        print(STDERR, "Authentication code: ")
        code = readline(STDIN) |> chomp
        status, header, content = curl("https://api.github.com/authorizations",AUTH_DATA,`-H "X-GitHub-OTP: $code" -u $user`)
    end
    status == 422 && error(github422(status, content))
    status != 401 && status != 403 || error(json().parse(content)["message"])
    tok = json().parse(content)["token"]
    mkpath(dirname(tokfile))
    open(io->println(io,tok),tokfile,"w")
    return tok
end

function req(resource::String, data, opts::Cmd=``)
    url = "https://api.github.com/$resource"
    status, header, content = curl(url,data,`-u $(token()):x-oauth-basic $opts`)
    response = json().parse(content)
    status, response
end

GET(resource::String, data, opts::Cmd=``) = req(resource,data,opts)
HEAD(resource::String, data, opts::Cmd=``) = req(resource,data,`-I $opts`)
PUT(resource::String, data, opts::Cmd=``) = req(resource,data,`-X PUT $opts`)
POST(resource::String, data, opts::Cmd=``) = req(resource,data,`-X POST $opts`)
PATCH(resource::String, data, opts::Cmd=``) = req(resource,data,`-X PATCH $opts`)
DELETE(resource::String, data, opts::Cmd=``) = req(resource,data,`-X DELETE $opts`)

for m in (:GET,:HEAD,:PUT,:POST,:PATCH,:DELETE)
    @eval $m(resource::String, opts::Cmd=``) = $m(resource,nothing,opts)
end

function pushable(owner::String, repo::String, user::String=user())
    status, response = HEAD("repos/$owner/$repo")
    status == 404 && error("repo $owner/$repo does not exist")
    status, response = GET("repos/$owner/$repo/collaborators/$user")
    status == 204 && return true
    status == 404 && return false
    error("unexpected API status code: $status – $(response["message"])")
end

function fork(owner::String, repo::String)
    status, response = POST("repos/$owner/$repo/forks")
    status == 202 || error("$forking $owner/$repo failed: $(response["message"])")
    return response
end

end # module
