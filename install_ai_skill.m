function install_ai_skill(target)
%INSTALL_AI_SKILL  Install the TMSIC skill for an AI assistant.
%
%   install_ai_skill('claude')   copy the skill to ~/.claude/skills/tmsic (Claude Code)
%   install_ai_skill('codex')    copy the skill to ~/.agents/skills/tmsic (OpenAI Codex)
%   install_ai_skill('zip')      write tmsic-skill.zip in the current folder (Claude.ai upload)
%   install_ai_skill('all')      claude and codex
%
%   The skill is the folder skills/tmsic: SKILL.md and a references folder.
%   For ChatGPT, see skills/README.md.

    if nargin < 1, target = 'claude'; end
    source = fullfile(fileparts(mfilename('fullpath')), 'skills', 'tmsic');
    assert(isfolder(source), 'TMSIC:installSkill', 'Cannot find %s.', source);
    home = char(java.lang.System.getProperty('user.home'));

    switch lower(target)
        case 'claude'
            copyTo(source, fullfile(home, '.claude', 'skills', 'tmsic'));
        case 'codex'
            copyTo(source, fullfile(home, '.agents', 'skills', 'tmsic'));
        case 'all'
            install_ai_skill('claude');
            install_ai_skill('codex');
        case 'zip'
            out = fullfile(pwd, 'tmsic-skill.zip');
            zip(out, 'tmsic', fileparts(source));
            fprintf('Wrote %s\nUpload it in Claude.ai under Settings, Capabilities, Skills.\n', out);
        otherwise
            error('TMSIC:installSkill', 'Unknown target "%s". Use claude, codex, zip or all.', target);
    end
end

function copyTo(source, destination)
    if isfolder(destination)
        rmdir(destination, 's');
    end
    mkdir(fileparts(destination));
    copyfile(source, destination);
    fprintf('Installed the TMSIC skill in %s\nRestart the assistant if it does not appear.\n', destination);
end
