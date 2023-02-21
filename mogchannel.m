classdef mogchannel < handle
    properties(SetAccess = protected)
        parent
    end
    
    properties
        freq
        pow
        phase
        mode
        signal
        amplifier
        powunits
        hasAmp
    end
    
    properties(SetAccess = immutable)
        channel
    end
    
    properties(Constant)
        FREQ_BITS = 32;
        CLK = 1e3;  %In MHz, so 1 GHz
        MODE = 'NSB';
    end
    
    methods
        function self = mogchannel(parent,channel,hasAmp)
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            end
            self.parent = parent;
            self.channel = channel;
            self.setDefaults;
            if nargin > 2
                self.hasAmp = hasAmp;
            else
                self.hasAmp = 1;
            end
        end
        
        function self = setDefaults(self)
            self.freq = 110;
            self.pow = 30;
            self.phase = 0;
            self.amplifier = 1;
            self.signal = 0;
            self.powunits = 'dbm';
        end
        
        function self = set(self,varargin)
            if mod(numel(varargin),2) ~= 0
                error('Arguments must be in name/value pairs!')
            else
                for nn = 1:2:numel(varargin)
                    v = varargin{nn+1};
                    switch lower(varargin{nn})
                        case 'freq'
                            self.freq = v;
                        case 'power'
                            self.pow = v;
                        case 'phase'
                            self.phase = v;
                        case 'signal'
                            self.signal = v;
                        case 'amplifier'
                            self.amplifier = v;
                        case 'powunits'
                            self.powunits = lower(v);
                        otherwise
                            error('Unknown property %s',varargin{nn});
                    end
                end
            end
        end
        
        function self = check(self)
            %Check frequency
            if self.freq > 400 || self.freq < 20
                error('Frequency %.6f MHz is out of range!',self.freq);
            end
            %Check power
            if strcmpi(self.powunits,'dbm') && self.pow > 35.87
                error('Power %.2f is out of range',self.pow);
            elseif strcmpi(self.powunits,'hex') && (self.pow > 2^16 || self.pow < 0)
                error('Power %d is out of range',round(self.pow));
            end
            %Wrap phase
            self.phase = mod(self.phase,360);            
        end
        
        function self = upload(self)
            self.check;
%             self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
            self.parent.cmd('freq,%d,%.6fMHz',self.channel,self.freq);
            if strcmpi(self.powunits,'dbm')
                self.parent.cmd('pow,%d,%.3fdBm',self.channel,self.pow);
            elseif strcmpi(self.powunits,'hex')
                self.parent.cmd('pow,%d,0x%04x',self.channel,round(self.pow));
            end
            self.parent.cmd('phase,%d,%.6fdeg',self.channel,self.phase);
            self.parent.cmd('%s,%d,sig',onoff(self.signal),self.channel);
            if self.hasAmp
                self.parent.cmd('%s,%d,pow',onoff(self.amplifier),self.channel);
            end
        end
        
        function self = write(self,varargin)
            self.set(varargin{:});
            self.upload;
        end
        
        function self = read(self)
            self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
            self.readFreq;
            self.readPow;
            self.readPhase;
            self.readStatus;
        end

        function f = readFreq(self)
            r = self.parent.ask('freq,%d',self.channel);
            r = regexp(r,'(?<=0x)\w+','match');
            f = hex2dec(r)/2^self.FREQ_BITS*self.CLK;
            self.freq = f;
        end
        
        function r = readPow(self)
            r = self.parent.ask('pow,%d',self.channel);
            if strcmpi(self.powunits,'dbm')
                r = str2double(regexp(r,'(\+|\-)\d+\.\d+','match'));
            elseif strcmpi(self.powunits,'hex')
                s = regexp(r,'0x\w+','match');
                r = hex2dec(s{1}(3:end));
            end
            self.pow = r;
        end
        
%         function r = readMode(self)
%             r = self.parent.ask('mode,%d',self.channel);
%             r = regexp(r,'(?<=\()\w+','match');
%             self.mode = r{1};
%         end
        
        function r = readPhase(self)
            r = self.parent.ask('phase,%d',self.channel);
            r = str2double(regexp(r,'^\d+\.\d+','match'));
            self.phase = r;
        end
        
        function r = readStatus(self)
            r = self.parent.ask('status,%d',self.channel);
            rsig = regexp(r,'(?<=SIG: )\w+','match');
            self.signal = onoff(rsig{1});
            rpow = regexp(r,'(?<=POW: )\w+','match');
            self.amplifier = onoff(rpow{1});
        end

    end

end

function r = onoff(v)
    if isnumeric(v)
        if v
            r = 'on';
        else
            r = 'off';
        end
    elseif ischar(v)
        if strcmpi(v,'on')
            r = 1;
        elseif strcmpi(v,'off')
            r = 0;
        end
    end
end