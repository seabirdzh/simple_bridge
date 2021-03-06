-module(simple_bridge_multipart_SUITE).

-include_lib("common_test/include/ct.hrl").

% Override with config variable {scratch_dir, Directory}
-define (SCRATCH_DIR, "./scratch").

-export([
    all/0,
    groups/0,
    init_per_group/2,
    end_per_group/2,
    end_per_testcase/2
]).

-export([
    post_mutlipart/1,
    post_mutlipart_post_too_big/1,
    post_mutlipart_file_too_big/1
]).

all() -> [{group, multipart}].

groups() -> [
    {multipart,
        [sequence, {repeat, 1}],
        [post_mutlipart, post_mutlipart_post_too_big, post_mutlipart_file_too_big]
    }].

init_per_group(_Group, Config) ->
    inets:start(),
    application:start(simple_bridge),
    Config.

end_per_group(_Group, Config) ->
    inets:stop(),
    application:stop(simple_bridge),
    Config.

end_per_testcase(_TestCase, _Config) ->
    lists:foreach(fun(File) -> file:delete(File) end, filelib:wildcard("./scratch/*")).

post_mutlipart(Config) ->
    BinStream1 = crypto:strong_rand_bytes(1024000),
    BinStream2 = crypto:strong_rand_bytes(2048000),
    Data1 = binary_to_list(BinStream1),
    Data2 = binary_to_list(BinStream2),
    Files = [{data, "data1", Data1}, {data, "data2", Data2}],

    {UploadedFiles, Errors} = binary_to_term(post_mutlipart("uploaded_files", Files)),

    2 = length(UploadedFiles),
    none = Errors,
    2 = length(get_all_files_from_scratch_dir()),
    lists:foreach(fun({AtomFieldName, FileName, FileContent}) ->
        FieldName = atom_to_list(AtomFieldName),
        BinaryFileContent = list_to_binary(FileContent),
        ByteSize = byte_size(BinaryFileContent),
        File = proplists:get_value(FileName, UploadedFiles),
        {ok, Binary} = file:read_file(sb_uploaded_file:temp_file(File)),

        ByteSize = sb_uploaded_file:size(File),
        FieldName = sb_uploaded_file:field_name(File),
        FileName = sb_uploaded_file:original_name(File),
        Binary = BinaryFileContent
    end, Files).

post_mutlipart_post_too_big(Config) ->
    BinStream1 = crypto:strong_rand_bytes(2048000),
    BinStream2 = crypto:strong_rand_bytes(2048000),
    Data1 = binary_to_list(BinStream1),
    Data2 = binary_to_list(BinStream2),
    Files = [{data, "data1", Data1}, {data, "data2", Data2}],

    {[], post_too_big} = binary_to_term(post_mutlipart("uploaded_files", Files)),
    [] = get_all_files_from_scratch_dir().

post_mutlipart_file_too_big(_) ->
    BinStream1 = crypto:strong_rand_bytes(1024),
    BinStream2 = crypto:strong_rand_bytes(3072000),
    Data1 = binary_to_list(BinStream1),
    Data2 = binary_to_list(BinStream2),
    Files = [{data, "data1", Data1}, {data, "data2", Data2}, {data, "data3", Data1}],

    {[], {file_too_big,"data2"}} = binary_to_term(post_mutlipart("uploaded_files", Files)),
    [] = get_all_files_from_scratch_dir().

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_all_files_from_scratch_dir() ->
    filelib:wildcard(filename:absname_join(simple_bridge_util:get_scratch_dir(?SCRATCH_DIR), "*")).

%% Based on http://stackoverflow.com/a/39284072
format_multipart_formdata(Boundary, Fields, Files) ->
    FieldParts = lists:map(fun({FieldName, FieldContent}) ->
        [lists:concat(["--", Boundary]),
         lists:concat(["Content-Disposition: form-data; name=\"",atom_to_list(FieldName),"\""]),
         "", FieldContent]
    end, Fields),

    FieldParts2 = lists:append(FieldParts),

    FileParts = lists:map(fun({FieldName, FileName, FileContent}) ->
        [lists:concat(["--", Boundary]),
         lists:concat(["Content-Disposition: form-data; name=\"",atom_to_list(FieldName),"\"; filename=\"",FileName,"\""]),
         lists:concat(["Content-Type: ", "application/octet-stream"]), "", FileContent]
    end, Files),

    FileParts2 = lists:append(FileParts),
    EndingParts = [lists:concat(["--", Boundary, "--"]), ""],
    Parts = lists:append([FieldParts2, FileParts2, EndingParts]),
    string:join(Parts, "\r\n").

post_mutlipart(Path, Files) ->
    Boundary = "------WebKitFormBoundaryUscTgwn7KiuepIr1",
    ReqBody = format_multipart_formdata(Boundary, [], Files),
    ContentType = lists:concat(["multipart/form-data; boundary=", Boundary]),
    ReqHeader = [{"Content-Length", integer_to_list(length(ReqBody))}],

    {ok, {_, _, Val}} = httpc:request(post,{"http://127.0.0.1:8000/" ++ Path, ReqHeader, ContentType, ReqBody},
                                      [], [{body_format, binary}]),
    Val.
