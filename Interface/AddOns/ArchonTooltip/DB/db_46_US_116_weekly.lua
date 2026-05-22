local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Shaman-Restoration','Mage-Frost','Hunter-Marksmanship','Unknown-Unknown','Mage-Fire','Shaman-Enhancement','Shaman-Elemental','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Mage-Arcane','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Druid-Feral','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Rogue-Subtlety','Monk-Brewmaster','Paladin-Retribution','Hunter-Survival','Paladin-Holy','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Blood','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAAALgAECgcJDgAAAA==.Aaramis:BAACLgAFFH8HAAIBAAIJ6QodQgB4AAABAAIJ6QodQgB4AAAuAAQKfy8AAgEACAkgFJU5AJsBAAEACAkgFJU5AJsBAAAA.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ac='Achin:BAAALgADCgUJBQAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAABLgAECn8UAAICAAgJEwSylwAQAQACAAgJEwSylwAQAQAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ai='Aidoffhealer:BAAALgAECgUJCwAAAA==.',
Al='Alariah:BAAALgAECggJEgAAAQ==.Alaín:BAABLgAECn8jAAIDAAgJtxiTBwDDAQADAAgJtxiTBwDDAQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgAEAAAAAA==.Aldoraline:BAAALgADCgIJAwAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAgAEAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgcJGAAFAEofAA==.',
Am='Ambellina:BAAALgAECgQJBQAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQABLgAECgEJAQAEAAAAAA==.',
An='Anaria:BAAALgAECgQJCAAAAA==.Angbu:BAABLgAECn8iAAMGAAcJPhdSDACBAQAGAAcJPhdSDACBAQAHAAEJoARgkQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAABLgAECn8iAAICAAcJthmJXQCFAQACAAcJthmJXQCFAQAAAA==.',
Ar='Aranyssa:BAABLgAECn8bAAQIAAkJyRrzCABqAQAIAAUJASLzCABqAQAJAAYJ3hHgoQAVAQAKAAMJ2hWLRQCgAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAQJEQAJAEsjAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8JAAILAAMJAQtjIwDUAAALAAMJAQtjIwDUAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Arnøld:BAAALgAECgEJAQAAAA==.Arruna:BAAALgAECgYJEQAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgcJGAAFAEofAA==.',
As='Asham:BAABLgAECn8mAAIMAAgJOQ2oHgB8AQAMAAgJOQ2oHgB8AQAAAA==.Ashenbloom:BAABLgAECn8bAAINAAgJfwhnTQASAQANAAgJfwhnTQASAQAAAA==.Asiago:BAABLgAECn8XAAMOAAkJ3hIgLQBYAQAOAAkJ3hIgLQBYAQAPAAEJRge0PwAxAAAAAA==.Aspect:BAABLgAECn8YAAMFAAcJSh/AAQATAgAFAAcJSh/AAQATAgACAAEJWRLEYAE/AAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBQAAAA==.',
Av='Avacúma:BAAALgAECgIJAwAAAA==.Avvalethra:BAABLgAECn8yAAMQAAkJexqYEACEAgAQAAkJexqYEACEAgADAAgJqA3XOwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJDAAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAcJFAAPAN8dAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Bachshots:BAAALgAFFAQJBAAAAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJCAAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCgAEAAAAAA==.Bananataffy:BAAALgAECgYJEQAAAA==.Barackoshama:BAABLgAECn8dAAIHAAkJAxx1EwD9AQAHAAkJAxx1EwD9AQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgcJFAAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn8vAAMCAAkJqBnhIQBYAgACAAkJqBnhIQBYAgARAAMJFwmTFQBvAAAAAA==.',
Be='Bearelf:BAAALgADCgIJAgAAAA==.Bearlinwall:BAAALgAECgYJEgAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.Bews:BAAALgAECgMJBAAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgQJBQABLgAFFAMJBQABAOwbAA==.Bigskydh:BAAALgAECgYJDwAAAA==.Bigskymage:BAAALgAECgUJDgAAAA==.Billybones:BAAALgAECgIJAwAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAFFAEJAQAEAAAAAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECggJIQASAH4MAA==.Bladedozzer:BAAALgAECgUJBwAAAA==.Blindinglite:BAABLgAECn8dAAITAAcJTCImDgCCAgATAAcJTCImDgCCAgAAAA==.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8KAAITAAMJLh8QCwANAQATAAMJLh8QCwANAQAuAAQKfx0AAhMACQmQHxgLAK8CABMACQmQHxgLAK8CAAAA.Blorp:BAACLgAFFH8NAAIUAAMJIBY3PADpAAAUAAMJIBY3PADpAAAuAAQKfxwAAhQACAnfHMwlAHACABQACAnfHMwlAHACAAAA.',
Bo='Bodizzle:BAAALgAECgEJAQAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCAAAAA==.Borestus:BAAALgAECgYJCQAAAA==.Bouldur:BAAALgAECgUJDgAAAA==.Bownystark:BAABLgAECn8eAAIDAAcJCCJHFQCIAgADAAcJCCJHFQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brickingit:BAAALgAECgYJBgAAAA==.Brieter:BAAALgAECgcJDAABLgAECgkJFwAOAN4SAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokendrako:BAAALgAFFAQJBAAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broly:BAAALgAECgEJAQAAAA==.Bromthelian:BAAALgADCgkJCQABLgAECgYJEAAEAAAAAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAABLgAECn8UAAIQAAYJcAq9dAD4AAAQAAYJcAq9dAD4AAAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAABLgAECn8YAAMVAAcJzh7CDQCZAQAVAAcJzh7CDQCZAQAWAAMJwQTOKABcAAAAAA==.Burntcring:BAAALgAECgUJBgAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAAALgAECgQJBgAAAA==.',
Ca='Camipriest:BAAALgAECgEJAQAAAA==.Carllina:BAAALgADCgMJAwAAAA==.Casstyelle:BAAALgAECgQJBAABLgAECgYJGAAIAPAWAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJGwAIAMkaAA==.Cet:BAAALgAECgQJBAABLgAECgcJGAAFAEofAA==.Cexiback:BAAALgAECgMJAwAAAA==.',
Ch='Chairon:BAAALgAECgMJAwABLgAECgUJEAAEAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgcJDAABLgAECgkJFwAOAN4SAA==.Chicharon:BAAALgAECgUJDwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECggJFgAXANgdAA==.Chipsnsalsa:BAAALgAECgQJBAABLgAECggJFgAXANgdAA==.Chocoriffic:BAABLgAECn8WAAIXAAgJ2B1bCQCKAgAXAAgJ2B1bCQCKAgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAECggJMQAYANEYAA==.Chokoballz:BAAALgAECgQJBQABLgAECggJMQAYANEYAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8sAAIVAAkJ9x5gAgDVAgAVAAkJ9x5gAgDVAgAAAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Corgibutts:BAAALgAECgIJAgAAAA==.',
Cr='Crackjones:BAAALgAECgYJBAAAAA==.Crapsrocks:BAAALgAECgQJBAAAAA==.Crazydave:BAABLgAECn8aAAIXAAkJ7xEoIwDMAQAXAAkJ7xEoIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwAEAAAAAA==.Crisgmt:BAAALgAECgcJCAAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAAALgAFFAEJAQAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAABLgAECn8dAAIZAAgJPSP3BQC5AgAZAAgJPSP3BQC5AgABLgAFFAYJFwACAAUZAA==.Cryptîc:BAACLgAFFH8XAAICAAYJBRnoEADNAQACAAYJBRnoEADNAQAuAAQKfzAAAgIACAnPJeUNANgCAAIACAnPJeUNANgCAAAA.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAICAAcJjxlOXwAdAgACAAcJjxlOXwAdAgAAAA==.Dabbia:BAACLgAFFH8FAAMIAAMJRhRGBgCfAAAIAAIJQBNGBgCfAAAJAAIJJg7LdgCOAAAuAAQKfx0ABAoACAmmHAkTALMBAAkABgl4G5JXAMEBAAoABgnlGgkTALMBAAgAAQlaIh8eAFgAAAAA.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAABLgAECn8YAAMIAAYJ8Ba4DQAPAQAIAAYJ8Ba4DQAPAQAJAAMJyw9GqwCoAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnpaw:BAABLgAECn8iAAMaAAkJqhNaIgCgAQAaAAgJcxFaIgCgAQAbAAUJpBXGLgD+AAAAAA==.Daymonesus:BAAALgAECgUJBQAAAA==.',
De='Deathballz:BAABLgAECn8xAAIYAAgJ0RhPNwDbAQAYAAgJ0RhPNwDbAQAAAA==.Deathsbreach:BAABLgAECn8VAAIUAAYJ4w8yagD9AAAUAAYJ4w8yagD9AAAAAA==.Deathsmite:BAAALgAECgIJAwAAAA==.Deathtee:BAABLgAECn8YAAIYAAgJqxxPRgAiAgAYAAgJqxxPRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Dekuslice:BAABLgAECn8aAAIcAAYJtBNDNQDnAAAcAAYJtBNDNQDnAAAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonarc:BAAALgAECgMJAwAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgAECgEJAQABLgAECgcJFwAJAFUIAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgAEAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgADCgcJCAAAAA==.',
Di='Dinkys:BAAALgADCgYJCwABLgAECgYJDwAEAAAAAA==.Dinsum:BAAALgADCgcJFAAAAA==.Diogenist:BAAALgAECgQJBQAAAA==.Dirtydhunter:BAAALgAECgYJBgAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAECgQJBQABLgAFFAMJBgAdAOskAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktardoodad:BAAALgAECgQJBwAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Donut:BAAALgADCgEJAQAAAA==.Doomslayer:BAABLgAECn8aAAIUAAkJfAn0YgB4AQAUAAkJfAn0YgB4AQAAAA==.Doresearch:BAABLgAECn8iAAIHAAgJkBW8HgCXAQAHAAgJkBW8HgCXAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8YAAIJAAgJSh8pKwDuAQAJAAgJSh8pKwDuAQAAAA==.Dragontee:BAAALgADCgQJBAABLgAECggJGAAYAKscAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBwAAAA==.Drakoswrath:BAAALgAECgUJBQAAAA==.Drengist:BAABLgAECn8xAAIeAAkJDho/CgBWAgAeAAkJDho/CgBWAgAAAA==.Drexybear:BAABLgAECn8cAAMQAAgJdCHiEACCAgAQAAgJdCHiEACCAgADAAUJBBcAQwBLAQAAAA==.Drezbi:BAAALgAECgUJDQAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.',
Du='Dulcineru:BAAALgADCgYJCgAAAA==.Dunbarth:BAABLgAECn8jAAIfAAkJbg2sUACNAQAfAAkJbg2sUACNAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAAALgAECgYJEwAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMJAAcJjxF/cgAZAQAJAAYJMRJ/cgAZAQAKAAIJZw5RTACIAAAAAA==.',
Ed='Eddai:BAAALgAECgEJAQAAAA==.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJGAAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elkanàh:BAAALgAFFAEJAQABLgAFFAMJBgAMAMIgAA==.Elleynle:BAAALgAECgQJDQAAAA==.Elunara:BAACLgAFFH8QAAIVAAQJVhYrBgAQAQAVAAQJVhYrBgAQAQAuAAQKfysAAhUACQlGHzYCANwCABUACQlGHzYCANwCAAEuAAQKCQkbAAgAyRoA.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.Emptor:BAAALgADCgEJAQAAAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8YAAMBAAYJsxJZSQAlAQABAAYJsxJZSQAlAQAHAAEJjAcAAAAAAAAAAA==.',
Es='Escanör:BAAALgAECgYJEAABLgAECgcJGAAFAEofAA==.Essekk:BAACLgAFFH8MAAICAAMJFRqELgD9AAACAAMJFRqELgD9AAAuAAQKfy8AAgIACQklH2AWACMDAAIACQklH2AWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evodrak:BAAALgADCgYJBwAAAA==.Evokeeznutz:BAAALgAECgcJCQABLgAFFAIJAwAEAAAAAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwAEAAAAAA==.',
['Eí']='Eír:BAAALgAECgUJBQABLgAECggJNQAXAOwdAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAAALgAECgYJDgAAAA==.Fao:BAAALgADCgMJAwAAAA==.Fastrialimas:BAAALgAECgEJBAAAAA==.Fatpo:BAABLgAECn8gAAMXAAgJzSC6BgDiAgAXAAgJzSC6BgDiAgAZAAQJVh/oMAAFAQAAAA==.Fayjhu:BAABLgAECn8mAAICAAgJaAvJagBmAQACAAgJaAvJagBmAQAAAA==.',
Fe='Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIJAAcJ7RB4cAAdAQAJAAcJ7RB4cAAdAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgADCgQJBAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8JAAIdAAQJoA+KEgA2AQAdAAQJoA+KEgA2AQAuAAQKfzAAAh0ACAniH/cJADkCAB0ACAniH/cJADkCAAAA.',
Fr='Frigate:BAABLgAECn8YAAICAAcJWgUS2QA/AQACAAcJWgUS2QA/AQAAAA==.Frihgate:BAABLgAECn8YAAIQAAcJXBd2MgDmAQAQAAcJXBd2MgDmAQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgEJAQABLgAECgkJDgAEAAAAAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8FAAIeAAMJjht6HQAHAQAeAAMJjht6HQAHAQAuAAQKfxYAAh4ACAl9IV0LAEQCAB4ACAl9IV0LAEQCAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgcJCAAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwAEAAAAAA==.',
Fy='Fyafya:BAAALgADCgEJAQAAAA==.Fyah:BAABLgAECn8ZAAIfAAkJhSB/TwDzAQAfAAkJhSB/TwDzAQABLgAFFAYJFgAgAI0fAA==.Fyaza:BAAALgAECgMJAwAAAA==.',
Ga='Gargamels:BAAALgAECgQJBgABLgAECgkJDgAEAAAAAA==.Gariantel:BAAALgAECgMJBQAAAA==.Garleck:BAAALgAECgMJAwAAAA==.Garou:BAABLgAECn8VAAILAAYJrBP8MgAvAQALAAYJrBP8MgAvAQAAAA==.Gaygar:BAAALgADCgYJDAABLgADCgcJDQAEAAAAAA==.',
Ge='Geekylock:BAAALgAECgUJDgAAAA==.Geekymage:BAAALgAECgMJAwAAAA==.Geekyxgenome:BAAALgADCgEJAQAAAA==.Genesis:BAAALgAECgkJAgAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgQJCwAAAA==.Gerttie:BAAALgAECgQJBAAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAcJKAAMAHwhAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECggJEwAAAA==.Gorehammer:BAABLgAECn8qAAIYAAgJlxmHUAAAAgAYAAgJlxmHUAAAAgAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgADCgYJBgAAAA==.Gravediger:BAAALgAECgYJCgAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAAALgAFFAIJAwAAAA==.Gridxx:BAAALgAECgcJEAAAAA==.Grievex:BAABLgAECn84AAIfAAkJzAlsVQCAAQAfAAkJzAlsVQCAAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.Grimblefritz:BAAALgADCgMJAwAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAAALgAECgcJBwAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAAALgAFFAEJAQAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemobloom:BAAALgAECgIJAgABLgAFFAQJFwAfALwbAA==.Hemolock:BAACLgAFFH8GAAIJAAQJmQMpSwDpAAAJAAQJmQMpSwDpAAAuAAQKfxwAAwkABgmAFrpgAEABAAkABgmAFrpgAEABAAoAAQkAAMxCAAAAAAEuAAUUBAkXAB8AvBsA.Hemostasis:BAACLgAFFH8XAAIfAAQJvBvwFgBhAQAfAAQJvBvwFgBhAQAuAAQKfycABB8ACAk/IpMwAGACAB8ACAk/IpMwAGACACEABAnKCYhSAJIAABIAAQksDrc7AC0AAAAA.Herjä:BAABLgAECn81AAMXAAgJ7B3QCwBdAgAXAAgJ7B3QCwBdAgAMAAYJrRNgJQBpAQAAAA==.Hexmora:BAAALgAECgEJAgAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Hoocha:BAAALgADCgYJBgABLgAFFAIJAwAEAAAAAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAgAAAA==.',
Hu='Hunterskillz:BAAALgADCgYJBgAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn8rAAIgAAkJpxqDCQBHAgAgAAkJpxqDCQBHAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgYJBgAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAAALgAFFAEJAQAAAA==.',
Il='Illuminee:BAAALgAECgIJAgABLgAECgIJAgAEAAAAAA==.Illydan:BAABLgAECn8VAAMUAAgJcRQCNQCnAQAUAAgJcRQCNQCnAQATAAEJGAilUQAqAAAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn82AAICAAkJTCBPDQDeAgACAAkJTCBPDQDeAgAAAA==.Impedup:BAAALgADCgYJBQAAAA==.',
In='Indigø:BAAALgAECgUJDQAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAEJAQAEAAAAAA==.',
Ir='Irezufortips:BAAALgAECgcJAQABLgAECgkJDgAEAAAAAA==.Ironhide:BAAALgAECgIJAgAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8VAAIfAAgJJw6+fQB+AQAfAAgJJw6+fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgQJBAAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECgIJAgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jimboslice:BAAALgADCgcJBwAAAA==.Jingleparts:BAAALgADCggJCQABLgAECggJFgAXANgdAA==.',
Jo='Joes:BAABLgAECn8dAAMQAAYJEhl7TgBcAQAQAAYJEhl7TgBcAQADAAYJ3AUTHACPAAAAAA==.Jonesy:BAAALgAECgUJCwAAAA==.Jorath:BAAALgAECgUJBQABLgAECgkJDgAEAAAAAA==.',
Ju='Juicygossip:BAAALgAECgYJBwAAAA==.Jujupowa:BAAALgAECgcJEwAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgAECgQJBAAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8WAAIgAAgJ3RExDwDSAQAgAAgJ3RExDwDSAQAAAA==.Kaidan:BAABLgAECn8jAAIQAAkJpBIBMADKAQAQAAkJpBIBMADKAQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgADCgYJBgAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAMJCAATAJUjAA==.Katanya:BAAALgAECgYJBgABLgAECgkJGwAIAMkaAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8QAAIQAAQJQxMiHgA9AQAQAAQJQxMiHgA9AQAAAA==.Keftheals:BAAALgAECgkJCgAAAA==.Keiriline:BAABLgAECn8fAAMiAAcJvRaICQBsAQAiAAcJvRaICQBsAQAYAAEJYwBnNAEZAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8YAAIgAAYJIB34HABnAQAgAAYJIB34HABnAQAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJGwAIAMkaAA==.',
Ki='Kiimari:BAAALgAECgIJAwAAAA==.Killbreed:BAABLgAECn8mAAIWAAgJVyEzAwCcAgAWAAgJVyEzAwCcAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgYJCgABLgAFFAQJBQAbAKgaAA==.Knuggz:BAABLgAECn8fAAILAAcJ3x8RIACgAQALAAcJ3x8RIACgAQAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCgkJEQAAAA==.',
Kr='Krestaul:BAAALgAECgcJCQAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAABLgAECn8qAAMJAAgJphwrKQD4AQAJAAgJphwrKQD4AQAKAAYJrwcMMQD1AAAAAA==.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8OAAIUAAQJ/xtwHABXAQAUAAQJ/xtwHABXAQAuAAQKfzwAAxQACQkiJsMAAHUDABQACQkiJsMAAHUDACMAAQluIf8jAGIAAAAA.Kyletotems:BAAALgADCggJCAAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Landridan:BAAALgAECgMJAwAAAA==.Lanstoll:BAAALgAECgIJAgAAAA==.Lanthin:BAAALgADCgYJCgAAAA==.Larzoh:BAABLgAECn8iAAMTAAkJ6iOkAwBGAwATAAkJ6iOkAwBGAwAUAAMJSw7WrwBnAAAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Lee:BAAALgADCgYJBQAAAA==.Legadiaus:BAAALgAECggJCQAAAA==.Lemonheads:BAABLgAECn8vAAMMAAgJCBc0EQAHAgAMAAgJCBc0EQAHAgAZAAEJ4QEtagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgQJCQAAAA==.Lidorila:BAAALgADCgYJDAAAAA==.Lightbranger:BAAALgADCgMJAwAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJEAAEAAAAAA==.Lilwiz:BAAALgAECgUJBQAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxvx:BAAALgAECgIJAgAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBAAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgAEAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwAEAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgAEAAAAAA==.',
Ls='Lshaman:BAABLgAFFH8FAAIBAAMJ7BtvJAD6AAABAAMJ7BtvJAD6AAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgADCgYJBgAAAA==.Lunahunter:BAAALgAECgEJAQAAAA==.Lunarcricket:BAAALgAECgUJCAABLgAECgkJKgASAIciAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwAEAAAAAA==.',
Ly='Lyncha:BAAALgADCgcJDgABLgAECgkJKgASAIciAA==.Lynchà:BAABLgAECn8qAAISAAkJhyLdAQDeAgASAAkJhyLdAQDeAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAECgkJKgASAIciAA==.',
Ma='Maakun:BAABLgAECn8dAAQXAAcJ3gxoOwBNAQAXAAcJ2gdoOwBNAQAZAAUJ8wcWQAD2AAAMAAQJHg2rOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJCwABLgAECgUJBgAEAAAAAA==.Madette:BAAALgADCggJCAABLgAFFAcJKAAMAHwhAA==.Mageapoug:BAAALgADCgcJBwAAAA==.Magmalance:BAAALgAECgYJCAABLgAECgYJFQAUAOMPAA==.Mahoragga:BAAALgADCgYJBgAAAA==.Mahzad:BAACLgAFFH8HAAIBAAQJGiH/DQCFAQABAAQJGiH/DQCFAQAuAAQKfyYAAwEABwljIzoYAFQCAAEABwljIzoYAFQCAAcABgmmDTs8AOoAAAAA.Maladi:BAAALgADCgkJJAAAAA==.Malfrun:BAABLgAECn8iAAMkAAkJKhYECwDxAQAkAAkJKhYECwDxAQALAAIJjQWlaQBVAAAAAA==.Marinnite:BAAALgADCgYJDQAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8IAAICAAQJwgqgRAAvAQACAAQJwgqgRAAvAQAuAAQKfxcAAgIACQmjHHZDAG4CAAIACQmjHHZDAG4CAAAA.Marshmellows:BAAALgAECgYJBgABLgAECgYJGAABALMSAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8RAAIJAAQJSyMVEwCTAQAJAAQJSyMVEwCTAQAuAAQKfyAAAwkACAk3I0oVANUCAAkABwk3I0oVANUCAAoAAQkAANtVAG0AAAAA.Matooka:BAABLgAECn8hAAIQAAgJEQ2oRAB7AQAQAAgJEQ2oRAB7AQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Me='Meencurry:BAABLgAECn8jAAICAAcJfBbSWwCKAQACAAcJfBbSWwCKAQAAAA==.Megozugzug:BAAALgAFFAEJAQAAAA==.Meyneth:BAAALgAECgQJBQAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgUJCgAAAA==.Mirlone:BAAALgAECgIJAgAAAA==.Misleading:BAAALgAECgUJCQAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Missdead:BAAALgAECgEJAQAAAA==.Mistfisting:BAACLgAFFH8FAAIaAAMJURT6HQDHAAAaAAMJURT6HQDHAAAuAAQKfxQAAhoABwmEHsIUAAUCABoABwmEHsIUAAUCAAAA.',
Mo='Moderato:BAAALgAECggJDQAAAA==.Moelleri:BAABLgAECn8bAAIYAAgJXRjiQAC6AQAYAAgJXRjiQAC6AQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBgAEAAAAAA==.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8OAAIaAAQJBQoTGgDwAAAaAAQJBQoTGgDwAAAuAAQKfx0AAxoACQmaFA8XAAkCABoACQmaFA8XAAkCABsABgnyCto5ADYBAAAA.Monsignor:BAAALgAECgEJBQAAAA==.Montra:BAACLgAFFH8HAAIVAAMJ6g6yCgDBAAAVAAMJ6g6yCgDBAAAuAAQKfzMAAxUACQkKHZMDAJwCABUACQkKHZMDAJwCABYABQkCCf4eAOsAAAAA.Moreilira:BAAALgAECgQJCAAAAA==.Mornshield:BAABLgAECn8fAAMfAAYJWxSmkQBZAQAfAAYJIxCmkQBZAQASAAUJUxMIJgDZAAABLgAECgkJDgAEAAAAAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAABLgAECn8YAAMNAAkJ5R3vBQAmAwANAAkJ5R3vBQAmAwAVAAMJFw/sKwB6AAAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8aAAIkAAgJohTOEgBuAQAkAAgJohTOEgBuAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGgAkAKIUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAfANocAA==.',
Na='Nahaine:BAAALgADCggJCAAAAA==.Nazrra:BAABLgAECn8bAAIkAAkJIxRkEAACAgAkAAkJIxRkEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJDwAYAK0TAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCgAAAA==.Newtnewt:BAAALgAECgUJBgAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgAECgEJAgABLgAECgYJEAAEAAAAAA==.Nirath:BAABLgAECn8vAAICAAgJFBCGWwCKAQACAAgJFBCGWwCKAQAAAA==.',
No='Nobainer:BAAALgADCgYJCgAAAA==.Noed:BAAALgAECgMJBgAAAA==.Nohkana:BAAALgAECgEJAQAAAA==.Nohkano:BAABLgAECn8mAAIeAAkJYyP1AQAhAwAeAAkJYyP1AQAhAwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECggJFgAXANgdAA==.Noobymonk:BAAALgAECggJEgAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8WAAIYAAcJKgVAowDaAAAYAAcJKgVAowDaAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAwAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgAECgQJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAICAAgJVhTDbAD8AQACAAgJVhTDbAD8AQAAAA==.',
Oa='Oakmain:BAAALgAECgUJBQAAAA==.',
Oc='Octavarium:BAABLgAECn8hAAIaAAgJEhzqDABnAgAaAAgJEhzqDABnAgAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgcJBwAAAA==.Odinsvulpera:BAAALgADCgYJBgAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBgAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJAwAAAA==.',
On='Oneshothel:BAAALgAECgYJEAAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAfANocAA==.',
Or='Orcpeon:BAAALgAECgYJDQABLgAECggJMwAfANEdAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECggJFgAXANgdAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Paichan:BAAALgAECgEJAQAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgUJBQAAAA==.Pancaked:BAAALgAECggJEAABLgAECggJFgAXANgdAA==.Pantheons:BAAALgADCgEJAQAAAA==.Paradox:BAAALgAECgQJBAABLgAFFAQJDAAWABsZAA==.Parsi:BAAALgAFFAIJAwAAAA==.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAABLgAECn8bAAICAAcJ+g/sbQBfAQACAAcJ+g/sbQBfAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgYJEAAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgAEAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgMJAwAAAA==.Pingdoo:BAAALgAECgIJAgAAAA==.',
Po='Pofat:BAABLgAFFH8GAAIaAAIJSyTmHADSAAAaAAIJSyTmHADSAAAAAA==.Polis:BAABLgAECn8zAAIfAAgJ0R22JgAgAgAfAAgJ0R22JgAgAgAAAA==.Pomol:BAAALgAECgcJDgAAAA==.Pomoly:BAAALgAECgEJAQAAAA==.Poppafury:BAAALgAECgcJDgAAAA==.Potent:BAABLgAECn8gAAMYAAgJ4REQWAB1AQAYAAgJ4REQWAB1AQAlAAQJbQaPOgBvAAAAAA==.Pougadina:BAAALgAECgIJAgABLgAECggJIAAXAM0gAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8IAAIYAAMJ1giXawDeAAAYAAMJ1giXawDeAAAuAAQKfxgAAxgACAn0Fpc/AL4BABgACAn0Fpc/AL4BACUAAQlLBH5PABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgcJEgABLgAECgkJDgAEAAAAAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIfAAYJYxaVhwAVAQAfAAYJYxaVhwAVAQAAAA==.Ramshunter:BAABLgAECn8fAAMQAAkJFiFcBwAaAwAQAAkJFiFcBwAaAwADAAIJ4xHtKQBCAAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgMJBQAAAA==.Ratnob:BAABLgAECn8uAAIYAAkJbRrhGQBoAgAYAAkJbRrhGQBoAgAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAIJAwAEAAAAAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAFFAEJAQAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAACLgAFFH8IAAITAAMJlSP6BwA4AQATAAMJlSP6BwA4AQAuAAQKfyEAAhMACQlBJAgEADsDABMACQlBJAgEADsDAAAA.Retpally:BAABLgAFFH8OAAIkAAUJNhF6BwBYAQAkAAUJNhF6BwBYAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8HAAIYAAMJJSXqQQA0AQAYAAMJJSXqQQA0AQAuAAQKfxgAAhgACQmGI6wJAOwCABgACQmGI6wJAOwCAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8VAAICAAcJPxHJmAAOAQACAAcJPxHJmAAOAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8NAAMgAAQJwRmNCABcAQAgAAQJwRmNCABcAQADAAIJOQ1KHwCZAAAuAAQKfy0AAwMACQmyIakNANgCAAMACAmhIakNANgCACAACAklGcwMABYCAAAA.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAACLgAFFH8GAAIdAAMJ6yTxEABAAQAdAAMJ6yTxEABAAQAuAAQKfyEAAh0ACQlvJRgBAEUDAB0ACQlvJRgBAEUDAAAA.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAAEAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8hAAMMAAkJCBfECgBwAgAMAAkJCBfECgBwAgAZAAEJdAAWbQAHAAAAAA==.Sakieri:BAABLgAECn84AAIZAAkJix5nBgCsAgAZAAkJix5nBgCsAgAAAA==.Salinomycin:BAAALgAECgYJDQAAAA==.Saltymcnalty:BAAALgAECgEJAQAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sandordel:BAAALgADCgYJCgAAAA==.Sangan:BAABLgAECn8XAAICAAYJpxt/YgB5AQACAAYJpxt/YgB5AQAAAA==.Sanguini:BAABLgAECn8mAAICAAgJxhjJOwDpAQACAAgJxhjJOwDpAQAAAA==.Sathari:BAAALgAECgQJCAAAAA==.',
Sc='Schmelzen:BAAALgAFFAQJBAAAAA==.Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQABLgAFFAEJAQAEAAAAAA==.Selaris:BAAALgAECgYJDAAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8UAAMPAAcJ3x3JAQCDAQAPAAQJmhvJAQCDAQAOAAYJXhuNDgCAAQAuAAQKfywAAw8ACQm9IsEBAC8DAA8ACAlJI8EBAC8DAA4ACAlGI2wGAL0CAAAA.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAQJCQAdAKAPAA==.Shangan:BAAALgAECgEJAQAAAA==.Sharana:BAAALgAECgQJBAAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgADCgYJDAAAAA==.Shirrazaha:BAAALgADCgMJAwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgAAAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgADCgYJBgAAAA==.',
Sk='Skeezer:BAAALgAFFAIJAwAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgAECgYJDAAAAA==.Slizzle:BAAALgAECgEJAQAAAA==.Slizzley:BAAALgAECgEJAgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCQABLgAFFAIJAwAEAAAAAA==.Smilingdemon:BAAALgAECgEJAQAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAAALgAECgYJDgAAAA==.Snarge:BAACLgAFFH8QAAIGAAUJIRUfBAA7AQAGAAUJIRUfBAA7AQAuAAQKfxkABAYACQkpGSAKADACAAYACQkpGSAKADACAAEABQltCGNmALoAAAcAAQkjEsaDADsAAAAA.Sneaktee:BAAALgAECgMJBAABLgAECggJGAAYAKscAA==.',
So='Soone:BAAALgAECgkJAQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgAECgYJBgABLgAECgYJFQAUAOMPAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spness:BAAALgAECgUJBQAAAA==.Spunky:BAAALgAECgQJBgAAAA==.',
Sq='Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAAALgAECgcJDwAAAA==.',
Sr='Srorcalot:BAAALgAECgcJEwABLgAECgkJDgAEAAAAAA==.',
St='Steppedon:BAAALgAECgYJEAAAAA==.Stingerai:BAABLgAECn8cAAIQAAkJJyCZEgBzAgAQAAkJJyCZEgBzAgABLgAECgkJLAAVAPceAA==.Stingeret:BAAALgADCgMJAwABLgAECgkJLAAVAPceAA==.Stingerge:BAAALgAECgMJBAABLgAECgkJLAAVAPceAA==.Stormweaverr:BAAALgAFFAEJAQABLgAFFAIJAwAEAAAAAA==.',
Su='Sunbeamer:BAAALgAECgUJCAAAAA==.Sureman:BAAALgAECgMJBQAAAA==.',
Sw='Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylvesters:BAAALgADCgcJBwABLgAECgUJBgAEAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
Ta='Tacosalad:BAAALgAECgcJCwABLgAECggJFgAXANgdAA==.Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Tamb:BAABLgAECn8dAAINAAYJVRT5QgA7AQANAAYJVRT5QgA7AQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Tark:BAAALgADCgYJBwAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwAEAAAAAA==.',
Te='Tedious:BAAALgAECgYJDAAAAA==.Teehuntee:BAAALgAECgMJAwABLgAECggJGAAYAKscAA==.Teepal:BAAALgAECgcJCwABLgAECggJGAAYAKscAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8aAAIGAAYJnx6/CgChAQAGAAYJnx6/CgChAQAAAA==.Teribullduce:BAACLgAFFH8JAAIgAAMJkBThEQABAQAgAAMJkBThEQABAQAuAAQKf0cAAiAACQk2Hn8EALACACAACQk2Hn8EALACAAAA.Terscheckii:BAAALgAFFAIJBAAAAA==.',
Th='Theslimer:BAAALgAECggJEgAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thormor:BAACLgAFFH8oAAIMAAcJfCGzAQDBAgAMAAcJfCGzAQDBAgAuAAQKfy4ABAwACQk8JPsAAJoDAAwACQk8JPsAAJoDABcABwnoHiMWACwCABkABQmVHp80AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAABLgAECn8pAAMfAAgJgBmTOQDTAQAfAAgJgBmTOQDTAQASAAIJbAb+NwA6AAAAAA==.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8hAAMSAAgJfgwDFwAUAQASAAgJfgwDFwAUAQAfAAMJHgoB/gCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tigg:BAAALgADCgQJBwAAAA==.Tiimmyy:BAAALgAECgQJBQAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDgAAAA==.Tinkertotem:BAAALgADCgkJCQAAAA==.Tinyandcute:BAAALgADCgkJCQABLgAECggJFgAXANgdAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgADCgYJBwABLgAECgYJGAAIAPAWAA==.',
Tr='Trebuchet:BAAALgAECgcJCAAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJFAAUAMIVAA==.Trtmiles:BAAALgAECgYJBgAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8dAAICAAcJzyBCKgAvAgACAAcJzyBCKgAvAgAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgMJBgAAAA==.',
Ub='Ubeenbained:BAABLgAECn8iAAITAAcJTw2AIwD1AAATAAcJTw2AIwD1AAAAAA==.',
Un='Unlock:BAABLgAECn8VAAIQAAcJfBfVOACmAQAQAAcJfBfVOACmAQAAAA==.',
Ur='Urgmathron:BAABLgAECn8VAAISAAYJayPuCADsAQASAAYJayPuCADsAQAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valadashora:BAAALgAECgEJAQAAAA==.Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8WAAMHAAUJnRKgDAAhAQAHAAQJnRKgDAAhAQABAAUJVwITHwAQAQAuAAQKfyUAAwcACQmzIH0FAM4CAAcACQmzIH0FAM4CAAEAAQlsGbyPAEQAAAAA.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgAECgQJDAAAAA==.',
Vd='Vdr:BAAALgADCgEJAQAAAA==.',
Ve='Velantheron:BAAALgAECgIJBAAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAAALgAECgUJDAAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.',
Vo='Voinox:BAAALgADCgcJDQAAAA==.Volcanoez:BAAALgAECgQJCwAAAA==.',
Vr='Vrezor:BAAALgAECgQJDAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMOAAcJ2BmDGAAMAgAOAAcJ2BmDGAAMAgAPAAEJtwIURgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warthelian:BAAALgADCgcJBwABLgAECgYJEAAEAAAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIfAAgJ2hwnJQCSAgAfAAgJ2hwnJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECggJDAAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJEgAEAAAAAA==.',
Wy='Wych:BAAALgAECgYJDwABLgAECggJGQAKANMeAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgYJEAAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgAECgYJBgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCAAAAA==.Yerrback:BAAALgAECgMJAwAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgADCgEJAQAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yur:BAAALgADCgcJDAABLgAECgcJGAAFAEofAA==.Yutch:BAAALgAECgYJCgAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgYJCwAAAA==.Zakkydrakky:BAABLgAECn8bAAMmAAcJnw4eEwBLAQAmAAcJnw4eEwBLAQAOAAUJtgg3TAClAAAAAA==.Zani:BAAALgAECgIJAgAAAA==.Zarashara:BAABLgAECn8lAAMeAAgJFBTtIABiAQAeAAcJEhbtIABiAQAbAAgJcAisKAAhAQAAAA==.',
Ze='Zedward:BAEALgAECgEJAQAAAA==.Zelta:BAAALgADCgkJEwAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgADCgkJDwAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAEJAQAEAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8gAAIfAAgJvRH4XgBpAQAfAAgJvRH4XgBpAQAAAA==.Zun:BAAALgAECggJDAAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Ód']='Ódinnhunt:BAAALgADCgEJAQAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMYAAgJRRRZVgDuAQAYAAgJ/BJZVgDuAQAiAAUJxAxbEwDCAAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
